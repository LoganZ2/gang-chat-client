#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <wincodec.h>

#include <cstdint>
#include <cstring>
#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kClipboardChannelName[] = "gang_chat/clipboard";
constexpr char kFileDropChannelName[] = "gang_chat/file_drop";
constexpr char kReadFilePathsMethod[] = "readFilePaths";
constexpr char kReadImageFileMethod[] = "readImageFile";
constexpr char kDropFilesMethod[] = "dropFiles";
constexpr wchar_t kFileDropWindowProp[] = L"GangChatFileDropWindow";
constexpr wchar_t kFileDropOriginalProcProp[] =
    L"GangChatFileDropOriginalProc";
constexpr DWORD kBiAlphaBitFields = 6;

template <typename T>
void SafeRelease(T*& value) {
  if (value) {
    value->Release();
    value = nullptr;
  }
}

std::string WideToUtf8(const wchar_t* value) {
  if (!value || value[0] == L'\0') {
    return {};
  }

  const int size = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0,
                                       nullptr, nullptr);
  if (size <= 1) {
    return {};
  }

  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value, -1, result.data(), size, nullptr,
                      nullptr);
  result.pop_back();
  return result;
}

bool EnsureComInitialized(bool* initialized_here) {
  *initialized_here = false;
  const HRESULT result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (SUCCEEDED(result)) {
    *initialized_here = true;
    return true;
  }
  return result == RPC_E_CHANGED_MODE;
}

size_t DibPixelOffset(const BITMAPINFOHEADER* header, size_t total_size) {
  if (!header || header->biSize < sizeof(BITMAPINFOHEADER) ||
      header->biSize > total_size) {
    return 0;
  }

  size_t offset = header->biSize;
  if (header->biSize == sizeof(BITMAPINFOHEADER) &&
      (header->biCompression == BI_BITFIELDS ||
       header->biCompression == kBiAlphaBitFields)) {
    offset += header->biCompression == kBiAlphaBitFields
                  ? 4 * sizeof(DWORD)
                  : 3 * sizeof(DWORD);
  }

  if (header->biBitCount <= 8) {
    const DWORD color_count =
        header->biClrUsed ? header->biClrUsed : (1u << header->biBitCount);
    offset += static_cast<size_t>(color_count) * sizeof(RGBQUAD);
  }

  return offset <= total_size ? offset : 0;
}

HGLOBAL CreateBmpGlobalFromDib(HGLOBAL dib_handle) {
  if (!dib_handle) {
    return nullptr;
  }

  const SIZE_T dib_size = GlobalSize(dib_handle);
  if (dib_size == 0) {
    return nullptr;
  }

  void* dib_data = GlobalLock(dib_handle);
  if (!dib_data) {
    return nullptr;
  }

  const auto* header = reinterpret_cast<const BITMAPINFOHEADER*>(dib_data);
  const size_t pixel_offset = DibPixelOffset(header, dib_size);
  if (pixel_offset == 0) {
    GlobalUnlock(dib_handle);
    return nullptr;
  }

  const SIZE_T bmp_size = sizeof(BITMAPFILEHEADER) + dib_size;
  HGLOBAL bmp_handle = GlobalAlloc(GMEM_MOVEABLE, bmp_size);
  if (!bmp_handle) {
    GlobalUnlock(dib_handle);
    return nullptr;
  }

  void* bmp_data = GlobalLock(bmp_handle);
  if (!bmp_data) {
    GlobalFree(bmp_handle);
    GlobalUnlock(dib_handle);
    return nullptr;
  }

  BITMAPFILEHEADER file_header{};
  file_header.bfType = 0x4D42;
  file_header.bfSize = static_cast<DWORD>(bmp_size);
  file_header.bfOffBits =
      static_cast<DWORD>(sizeof(BITMAPFILEHEADER) + pixel_offset);

  std::memcpy(bmp_data, &file_header, sizeof(file_header));
  std::memcpy(static_cast<uint8_t*>(bmp_data) + sizeof(file_header), dib_data,
              dib_size);

  GlobalUnlock(bmp_handle);
  GlobalUnlock(dib_handle);
  return bmp_handle;
}

std::optional<std::vector<uint8_t>> StreamBytes(IStream* stream) {
  if (!stream) {
    return std::nullopt;
  }

  HGLOBAL global = nullptr;
  if (FAILED(GetHGlobalFromStream(stream, &global)) || !global) {
    return std::nullopt;
  }

  const SIZE_T size = GlobalSize(global);
  if (size == 0) {
    return std::nullopt;
  }

  void* data = GlobalLock(global);
  if (!data) {
    return std::nullopt;
  }

  std::vector<uint8_t> bytes(size);
  std::memcpy(bytes.data(), data, size);
  GlobalUnlock(global);
  return bytes;
}

std::optional<std::vector<uint8_t>> EncodeBitmapSourceToPng(
    IWICImagingFactory* factory,
    IWICBitmapSource* source) {
  if (!factory || !source) {
    return std::nullopt;
  }

  IWICFormatConverter* converter = nullptr;
  IWICBitmapSource* source_to_write = source;
  if (SUCCEEDED(factory->CreateFormatConverter(&converter)) &&
      SUCCEEDED(converter->Initialize(source, GUID_WICPixelFormat32bppBGRA,
                                      WICBitmapDitherTypeNone, nullptr, 0.0,
                                      WICBitmapPaletteTypeCustom))) {
    source_to_write = converter;
  }

  UINT width = 0;
  UINT height = 0;
  if (FAILED(source_to_write->GetSize(&width, &height)) || width == 0 ||
      height == 0) {
    SafeRelease(converter);
    return std::nullopt;
  }

  IStream* output_stream = nullptr;
  IWICBitmapEncoder* encoder = nullptr;
  IWICBitmapFrameEncode* frame = nullptr;
  IPropertyBag2* properties = nullptr;
  std::optional<std::vector<uint8_t>> result;

  if (SUCCEEDED(CreateStreamOnHGlobal(nullptr, TRUE, &output_stream)) &&
      SUCCEEDED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr,
                                       &encoder)) &&
      SUCCEEDED(
          encoder->Initialize(output_stream, WICBitmapEncoderNoCache)) &&
      SUCCEEDED(encoder->CreateNewFrame(&frame, &properties)) &&
      SUCCEEDED(frame->Initialize(properties)) &&
      SUCCEEDED(frame->SetSize(width, height))) {
    WICPixelFormatGUID pixel_format = GUID_WICPixelFormat32bppBGRA;
    if (SUCCEEDED(frame->SetPixelFormat(&pixel_format)) &&
        SUCCEEDED(frame->WriteSource(source_to_write, nullptr)) &&
        SUCCEEDED(frame->Commit()) && SUCCEEDED(encoder->Commit())) {
      result = StreamBytes(output_stream);
    }
  }

  SafeRelease(properties);
  SafeRelease(frame);
  SafeRelease(encoder);
  SafeRelease(output_stream);
  SafeRelease(converter);
  return result;
}

std::optional<std::vector<uint8_t>> EncodeDibToPng(
    IWICImagingFactory* factory,
    HGLOBAL dib_handle) {
  HGLOBAL bmp_handle = CreateBmpGlobalFromDib(dib_handle);
  if (!bmp_handle) {
    return std::nullopt;
  }

  IStream* bmp_stream = nullptr;
  IWICBitmapDecoder* decoder = nullptr;
  IWICBitmapFrameDecode* frame = nullptr;
  std::optional<std::vector<uint8_t>> result;

  if (SUCCEEDED(CreateStreamOnHGlobal(bmp_handle, TRUE, &bmp_stream))) {
    if (SUCCEEDED(factory->CreateDecoderFromStream(
            bmp_stream, nullptr, WICDecodeMetadataCacheOnLoad, &decoder)) &&
        SUCCEEDED(decoder->GetFrame(0, &frame))) {
      result = EncodeBitmapSourceToPng(factory, frame);
    }
  } else {
    GlobalFree(bmp_handle);
  }

  SafeRelease(frame);
  SafeRelease(decoder);
  SafeRelease(bmp_stream);
  return result;
}

std::optional<std::vector<uint8_t>> EncodeHBitmapToPng(
    IWICImagingFactory* factory,
    HBITMAP bitmap) {
  if (!factory || !bitmap) {
    return std::nullopt;
  }

  IWICBitmap* source = nullptr;
  std::optional<std::vector<uint8_t>> result;
  if (SUCCEEDED(factory->CreateBitmapFromHBITMAP(
          bitmap, nullptr, WICBitmapIgnoreAlpha, &source))) {
    result = EncodeBitmapSourceToPng(factory, source);
  }
  SafeRelease(source);
  return result;
}

std::optional<std::vector<uint8_t>> ReadClipboardImagePng(HWND owner) {
  if (!IsClipboardFormatAvailable(CF_DIBV5) &&
      !IsClipboardFormatAvailable(CF_DIB) &&
      !IsClipboardFormatAvailable(CF_BITMAP)) {
    return std::nullopt;
  }
  if (!OpenClipboard(owner)) {
    return std::nullopt;
  }

  bool com_initialized_here = false;
  IWICImagingFactory* factory = nullptr;
  std::optional<std::vector<uint8_t>> result;
  if (EnsureComInitialized(&com_initialized_here) &&
      SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                 CLSCTX_INPROC_SERVER,
                                 IID_PPV_ARGS(&factory)))) {
    if (IsClipboardFormatAvailable(CF_DIBV5)) {
      result = EncodeDibToPng(
          factory, static_cast<HGLOBAL>(GetClipboardData(CF_DIBV5)));
    }
    if (!result && IsClipboardFormatAvailable(CF_DIB)) {
      result = EncodeDibToPng(
          factory, static_cast<HGLOBAL>(GetClipboardData(CF_DIB)));
    }
    if (!result && IsClipboardFormatAvailable(CF_BITMAP)) {
      result = EncodeHBitmapToPng(
          factory, static_cast<HBITMAP>(GetClipboardData(CF_BITMAP)));
    }
  }

  SafeRelease(factory);
  CloseClipboard();
  if (com_initialized_here) {
    CoUninitialize();
  }
  return result;
}

flutter::EncodableList ReadDropFilePaths(HDROP drop) {
  flutter::EncodableList paths;
  if (!drop) {
    return paths;
  }

  const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  for (UINT i = 0; i < count; ++i) {
    const UINT length = DragQueryFileW(drop, i, nullptr, 0);
    if (length == 0) {
      continue;
    }

    std::vector<wchar_t> buffer(length + 1);
    if (DragQueryFileW(drop, i, buffer.data(),
                       static_cast<UINT>(buffer.size())) == 0) {
      continue;
    }

    const std::string path = WideToUtf8(buffer.data());
    if (!path.empty()) {
      paths.emplace_back(path);
    }
  }
  return paths;
}

double LogicalDropCoordinate(HWND window, LONG value) {
  const UINT dpi = GetDpiForWindow(window);
  const double scale = dpi > 0 ? static_cast<double>(dpi) / 96.0 : 1.0;
  return static_cast<double>(value) / scale;
}

LRESULT CALLBACK FileDropChildProc(HWND window, UINT const message,
                                   WPARAM const wparam,
                                   LPARAM const lparam) noexcept {
  auto flutter_window =
      reinterpret_cast<FlutterWindow*>(GetPropW(window, kFileDropWindowProp));
  if (flutter_window && message == WM_DROPFILES) {
    flutter_window->HandleNativeFileDrop(
        window, reinterpret_cast<HDROP>(wparam));
    return 0;
  }

  WNDPROC original_proc = reinterpret_cast<WNDPROC>(
      GetPropW(window, kFileDropOriginalProcProp));
  if (original_proc) {
    return CallWindowProc(original_proc, window, message, wparam, lparam);
  }
  return DefWindowProc(window, message, wparam, lparam);
}

flutter::EncodableList ReadClipboardFilePaths(HWND owner) {
  flutter::EncodableList paths;
  if (!IsClipboardFormatAvailable(CF_HDROP) || !OpenClipboard(owner)) {
    return paths;
  }

  const HANDLE data = GetClipboardData(CF_HDROP);
  if (data) {
    paths = ReadDropFilePaths(static_cast<HDROP>(data));
  }

  CloseClipboard();
  return paths;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::AttachFileDropTarget(HWND child_window) {
  DragAcceptFiles(GetHandle(), TRUE);
  if (!child_window) {
    return;
  }

  file_drop_child_window_ = child_window;
  DragAcceptFiles(file_drop_child_window_, TRUE);
  SetPropW(file_drop_child_window_, kFileDropWindowProp, this);
  original_child_proc_ = reinterpret_cast<WNDPROC>(SetWindowLongPtr(
      file_drop_child_window_, GWLP_WNDPROC,
      reinterpret_cast<LONG_PTR>(FileDropChildProc)));
  SetPropW(file_drop_child_window_, kFileDropOriginalProcProp,
           reinterpret_cast<HANDLE>(original_child_proc_));
}

void FlutterWindow::DetachFileDropTarget() {
  if (GetHandle()) {
    DragAcceptFiles(GetHandle(), FALSE);
  }
  if (file_drop_child_window_) {
    DragAcceptFiles(file_drop_child_window_, FALSE);
    if (original_child_proc_) {
      SetWindowLongPtr(file_drop_child_window_, GWLP_WNDPROC,
                       reinterpret_cast<LONG_PTR>(original_child_proc_));
    }
    RemovePropW(file_drop_child_window_, kFileDropWindowProp);
    RemovePropW(file_drop_child_window_, kFileDropOriginalProcProp);
  }
  file_drop_child_window_ = nullptr;
  original_child_proc_ = nullptr;
}

void FlutterWindow::HandleNativeFileDrop(HWND window, HDROP drop) {
  POINT point{};
  DragQueryPoint(drop, &point);
  flutter::EncodableList paths = ReadDropFilePaths(drop);
  DragFinish(drop);
  if (paths.empty() || !file_drop_channel_) {
    return;
  }

  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("paths")] = flutter::EncodableValue(paths);
  arguments[flutter::EncodableValue("x")] =
      flutter::EncodableValue(LogicalDropCoordinate(window, point.x));
  arguments[flutter::EncodableValue("y")] =
      flutter::EncodableValue(LogicalDropCoordinate(window, point.y));
  file_drop_channel_->InvokeMethod(
      kDropFilesMethod, std::make_unique<flutter::EncodableValue>(arguments));
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  auto clipboard_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kClipboardChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  clipboard_channel->SetMethodCallHandler(
      [this](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        if (call.method_name() == kReadFilePathsMethod) {
          result->Success(ReadClipboardFilePaths(GetHandle()));
          return;
        }
        if (call.method_name() == kReadImageFileMethod) {
          const auto bytes = ReadClipboardImagePng(GetHandle());
          if (!bytes || bytes->empty()) {
            result->Success(flutter::EncodableValue());
            return;
          }
          flutter::EncodableMap image_file;
          image_file[flutter::EncodableValue("filename")] =
              flutter::EncodableValue("clipboard-image.png");
          image_file[flutter::EncodableValue("mime_type")] =
              flutter::EncodableValue("image/png");
          image_file[flutter::EncodableValue("bytes")] =
              flutter::EncodableValue(*bytes);
          result->Success(flutter::EncodableValue(image_file));
          return;
        }
        result->NotImplemented();
      });
  clipboard_channel_ = std::move(clipboard_channel);
  file_drop_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kFileDropChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  AttachFileDropTarget(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    DetachFileDropTarget();
    file_drop_channel_ = nullptr;
    clipboard_channel_ = nullptr;
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_DROPFILES:
      HandleNativeFileDrop(hwnd, reinterpret_cast<HDROP>(wparam));
      return 0;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
