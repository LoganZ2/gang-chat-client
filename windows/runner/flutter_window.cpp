#include "flutter_window.h"

#include <propkeydef.h>
#include <functiondiscoverykeys_devpkey.h>
#include <flutter/standard_method_codec.h>
#include <mmdeviceapi.h>
#include <propsys.h>
#include <shellapi.h>
#include <wincodec.h>

#include <cstdint>
#include <cstring>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kClipboardChannelName[] = "gang_chat/clipboard";
constexpr char kFileDropChannelName[] = "gang_chat/file_drop";
constexpr char kAudioDevicesChannelName[] = "gang_chat/audio_devices";
constexpr char kReadFilePathsMethod[] = "readFilePaths";
constexpr char kReadImageFileMethod[] = "readImageFile";
constexpr char kDropFilesMethod[] = "dropFiles";
constexpr char kEnumerateInputsMethod[] = "enumerateInputs";
constexpr char kEnumerateOutputsMethod[] = "enumerateOutputs";
constexpr char kDefaultInputDeviceIdMethod[] = "getDefaultInputDeviceId";
constexpr char kDefaultOutputDeviceIdMethod[] = "getDefaultOutputDeviceId";
constexpr char kStartListeningMethod[] = "startListening";
constexpr char kDefaultInputDeviceChangedMethod[] = "defaultInputDeviceChanged";
constexpr char kDefaultOutputDeviceChangedMethod[] =
    "defaultOutputDeviceChanged";
constexpr wchar_t kFileDropWindowProp[] = L"GangChatFileDropWindow";
constexpr wchar_t kFileDropOriginalProcProp[] =
    L"GangChatFileDropOriginalProc";
constexpr DWORD kBiAlphaBitFields = 6;
constexpr UINT kAudioDefaultDeviceChangedMessage = WM_APP + 0x4A2;

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

class ScopedComInitialization {
 public:
  ScopedComInitialization() : ok_(EnsureComInitialized(&initialized_here_)) {}

  ~ScopedComInitialization() {
    if (initialized_here_) {
      CoUninitialize();
    }
  }

  bool ok() const { return ok_; }

 private:
  bool initialized_here_ = false;
  bool ok_ = false;
};

struct AudioDeviceChange {
  AudioDeviceChange(EDataFlow flow, std::string device_id)
      : flow(flow), device_id(std::move(device_id)) {}

  EDataFlow flow;
  std::string device_id;
};

class AudioDeviceNotificationClient final : public IMMNotificationClient {
 public:
  explicit AudioDeviceNotificationClient(
      std::function<void(EDataFlow, std::string)> on_default_changed)
      : on_default_changed_(std::move(on_default_changed)) {}

  ULONG STDMETHODCALLTYPE AddRef() override {
    return static_cast<ULONG>(InterlockedIncrement(&ref_count_));
  }

  ULONG STDMETHODCALLTYPE Release() override {
    const LONG count = InterlockedDecrement(&ref_count_);
    if (count == 0) {
      delete this;
    }
    return static_cast<ULONG>(count);
  }

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** object) override {
    if (!object) {
      return E_POINTER;
    }
    if (riid == __uuidof(IUnknown) ||
        riid == __uuidof(IMMNotificationClient)) {
      *object = static_cast<IMMNotificationClient*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }

  HRESULT STDMETHODCALLTYPE OnDefaultDeviceChanged(
      EDataFlow flow,
      ERole role,
      LPCWSTR default_device_id) override {
    if (role == eConsole && (flow == eCapture || flow == eRender)) {
      on_default_changed_(flow, WideToUtf8(default_device_id));
    }
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE OnDeviceAdded(LPCWSTR device_id) override {
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE OnDeviceRemoved(LPCWSTR device_id) override {
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE OnDeviceStateChanged(LPCWSTR device_id,
                                                 DWORD new_state) override {
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE OnPropertyValueChanged(
      LPCWSTR device_id,
      const PROPERTYKEY key) override {
    return S_OK;
  }

 private:
  volatile LONG ref_count_ = 1;
  std::function<void(EDataFlow, std::string)> on_default_changed_;
};

std::optional<std::string> AudioEndpointId(IMMDevice* device) {
  if (!device) {
    return std::nullopt;
  }
  wchar_t* raw_id = nullptr;
  if (FAILED(device->GetId(&raw_id)) || !raw_id) {
    return std::nullopt;
  }
  const std::string device_id = WideToUtf8(raw_id);
  CoTaskMemFree(raw_id);
  if (device_id.empty()) {
    return std::nullopt;
  }
  return device_id;
}

std::string AudioEndpointFriendlyName(IMMDevice* device,
                                      const std::string& fallback) {
  if (!device) {
    return fallback;
  }

  IPropertyStore* properties = nullptr;
  PROPVARIANT name;
  PropVariantInit(&name);
  std::string label;
  if (SUCCEEDED(device->OpenPropertyStore(STGM_READ, &properties)) &&
      SUCCEEDED(properties->GetValue(PKEY_Device_FriendlyName, &name)) &&
      name.vt == VT_LPWSTR) {
    label = WideToUtf8(name.pwszVal);
  }

  PropVariantClear(&name);
  SafeRelease(properties);
  return label.empty() ? fallback : label;
}

std::optional<std::string> DefaultAudioEndpointIdFromEnumerator(
    IMMDeviceEnumerator* enumerator,
    EDataFlow flow) {
  if (!enumerator) {
    return std::nullopt;
  }

  IMMDevice* device = nullptr;
  std::optional<std::string> result;
  if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(flow, eConsole, &device))) {
    result = AudioEndpointId(device);
  }
  SafeRelease(device);
  return result;
}

std::optional<std::string> DefaultAudioEndpointId(EDataFlow flow) {
  ScopedComInitialization com;
  if (!com.ok()) {
    return std::nullopt;
  }

  IMMDeviceEnumerator* enumerator = nullptr;
  std::optional<std::string> result;
  if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                 CLSCTX_ALL, IID_PPV_ARGS(&enumerator)))) {
    result = DefaultAudioEndpointIdFromEnumerator(enumerator, flow);
  }
  SafeRelease(enumerator);
  return result;
}

flutter::EncodableValue NullableStringValue(
    const std::optional<std::string>& value) {
  return value && !value->empty() ? flutter::EncodableValue(*value)
                                  : flutter::EncodableValue();
}

flutter::EncodableList EnumerateAudioEndpoints(EDataFlow flow,
                                               const std::string& fallback) {
  flutter::EncodableList devices;
  ScopedComInitialization com;
  if (!com.ok()) {
    return devices;
  }

  IMMDeviceEnumerator* enumerator = nullptr;
  IMMDeviceCollection* collection = nullptr;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                              CLSCTX_ALL, IID_PPV_ARGS(&enumerator))) ||
      FAILED(enumerator->EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE,
                                            &collection))) {
    SafeRelease(collection);
    SafeRelease(enumerator);
    return devices;
  }

  const auto default_id = DefaultAudioEndpointIdFromEnumerator(enumerator, flow);
  UINT count = 0;
  if (SUCCEEDED(collection->GetCount(&count))) {
    for (UINT i = 0; i < count; ++i) {
      IMMDevice* device = nullptr;
      if (FAILED(collection->Item(i, &device))) {
        continue;
      }
      const auto device_id = AudioEndpointId(device);
      if (device_id) {
        flutter::EncodableMap entry;
        entry[flutter::EncodableValue("deviceId")] =
            flutter::EncodableValue(*device_id);
        entry[flutter::EncodableValue("label")] = flutter::EncodableValue(
            AudioEndpointFriendlyName(device, fallback + " " + *device_id));
        entry[flutter::EncodableValue("isDefault")] =
            flutter::EncodableValue(default_id && *default_id == *device_id);
        devices.emplace_back(entry);
      }
      SafeRelease(device);
    }
  }

  SafeRelease(collection);
  SafeRelease(enumerator);
  return devices;
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

void FlutterWindow::RegisterAudioDevicesChannel() {
  audio_devices_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kAudioDevicesChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  audio_devices_channel_->SetMethodCallHandler(
      [this](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        if (call.method_name() == kEnumerateInputsMethod) {
          result->Success(EnumerateAudioEndpoints(eCapture, "Microphone"));
          return;
        }
        if (call.method_name() == kEnumerateOutputsMethod) {
          result->Success(EnumerateAudioEndpoints(eRender, "Speaker"));
          return;
        }
        if (call.method_name() == kDefaultInputDeviceIdMethod) {
          result->Success(NullableStringValue(DefaultAudioEndpointId(eCapture)));
          return;
        }
        if (call.method_name() == kDefaultOutputDeviceIdMethod) {
          result->Success(NullableStringValue(DefaultAudioEndpointId(eRender)));
          return;
        }
        if (call.method_name() == kStartListeningMethod) {
          EnsureAudioDeviceNotifications();
          result->Success(flutter::EncodableValue());
          return;
        }
        result->NotImplemented();
      });
}

bool FlutterWindow::EnsureAudioDeviceNotifications() {
  if (audio_device_enumerator_ && audio_device_notification_client_) {
    return true;
  }

  if (!audio_device_enumerator_) {
    bool initialized_here = false;
    if (!EnsureComInitialized(&initialized_here)) {
      return false;
    }
    if (initialized_here) {
      audio_com_initialized_here_ = true;
    }
    if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL,
                                IID_PPV_ARGS(&audio_device_enumerator_)))) {
      if (initialized_here && audio_com_initialized_here_) {
        CoUninitialize();
        audio_com_initialized_here_ = false;
      }
      return false;
    }
  }

  if (!audio_device_notification_client_) {
    auto* client = new AudioDeviceNotificationClient(
        [this](EDataFlow flow, std::string device_id) {
          auto* change =
              new AudioDeviceChange(flow, std::move(device_id));
          if (!PostMessage(GetHandle(), kAudioDefaultDeviceChangedMessage, 0,
                           reinterpret_cast<LPARAM>(change))) {
            delete change;
          }
        });
    if (FAILED(audio_device_enumerator_->RegisterEndpointNotificationCallback(
            client))) {
      client->Release();
      return false;
    }
    audio_device_notification_client_ = client;
  }

  return true;
}

void FlutterWindow::DetachAudioDeviceNotifications() {
  if (audio_device_enumerator_ && audio_device_notification_client_) {
    audio_device_enumerator_->UnregisterEndpointNotificationCallback(
        audio_device_notification_client_);
  }
  SafeRelease(audio_device_notification_client_);
  SafeRelease(audio_device_enumerator_);
  if (audio_com_initialized_here_) {
    CoUninitialize();
    audio_com_initialized_here_ = false;
  }
}

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
  RegisterAudioDevicesChannel();
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
    DetachAudioDeviceNotifications();
    DetachFileDropTarget();
    file_drop_channel_ = nullptr;
    audio_devices_channel_ = nullptr;
    clipboard_channel_ = nullptr;
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kAudioDefaultDeviceChangedMessage) {
    std::unique_ptr<AudioDeviceChange> change(
        reinterpret_cast<AudioDeviceChange*>(lparam));
    if (change && audio_devices_channel_) {
      const char* method = change->flow == eCapture
                               ? kDefaultInputDeviceChangedMethod
                               : kDefaultOutputDeviceChangedMethod;
      auto argument = change->device_id.empty()
                          ? std::make_unique<flutter::EncodableValue>()
                          : std::make_unique<flutter::EncodableValue>(
                                change->device_id);
      audio_devices_channel_->InvokeMethod(method, std::move(argument));
    }
    return 0;
  }

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
