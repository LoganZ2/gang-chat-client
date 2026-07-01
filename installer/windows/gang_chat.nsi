Unicode true

!ifndef APP_VERSION
!define APP_VERSION "0.0.0"
!endif

!ifndef APP_VERSION_QUAD
!define APP_VERSION_QUAD "${APP_VERSION}.0"
!endif

!ifndef PROJECT_ROOT
!define PROJECT_ROOT "..\.."
!endif

!ifndef SOURCE_DIR
!define SOURCE_DIR "${PROJECT_ROOT}\build\windows\x64\runner\Release"
!endif

!ifndef OUTPUT_FILE
!define OUTPUT_FILE "${PROJECT_ROOT}\GangChat-${APP_VERSION}-windows-installer.exe"
!endif

!define APP_NAME "Gang Chat"
!define APP_PUBLISHER "Gang Chat"
!define APP_EXE "client.exe"

!if /FileExists "${SOURCE_DIR}\${APP_EXE}"
!else
!error "Missing Flutter Windows release build at ${SOURCE_DIR}."
!endif

Name "${APP_NAME}"
OutFile "${OUTPUT_FILE}"
InstallDir "$PROGRAMFILES64\Gang Chat"
InstallDirRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "InstallLocation"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
SetCompressorDictSize 64

Icon "${PROJECT_ROOT}\windows\runner\resources\app_icon.ico"
UninstallIcon "${PROJECT_ROOT}\windows\runner\resources\app_icon.ico"

VIProductVersion "${APP_VERSION_QUAD}"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "CompanyName" "${APP_PUBLISHER}"
VIAddVersionKey "FileDescription" "${APP_NAME} Installer"
VIAddVersionKey "FileVersion" "${APP_VERSION}"
VIAddVersionKey "ProductVersion" "${APP_VERSION}"
VIAddVersionKey "LegalCopyright" "Copyright (C) 2026 ${APP_PUBLISHER}. All rights reserved."

!include "MUI2.nsh"
!include "FileFunc.nsh"
!insertmacro GetTime

!define MUI_ABORTWARNING
!define MUI_ICON "${PROJECT_ROOT}\windows\runner\resources\app_icon.ico"
!define MUI_UNICON "${PROJECT_ROOT}\windows\runner\resources\app_icon.ico"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Section "Install"
  SetShellVarContext all

  SetOutPath "$INSTDIR"
  File /r "${SOURCE_DIR}\*.*"
  ${GetTime} "" "L" $0 $1 $2 $3 $4 $5 $6
  FileOpen $7 "$INSTDIR\gang_chat_install_info.txt" w
  FileWrite $7 "$2/$1/$0"
  FileClose $7

  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$SMPROGRAMS\Gang Chat"
  CreateShortcut "$SMPROGRAMS\Gang Chat\Gang Chat.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  CreateShortcut "$SMPROGRAMS\Gang Chat\Uninstall Gang Chat.lnk" "$INSTDIR\Uninstall.exe" "" "$INSTDIR\Uninstall.exe" 0
  CreateShortcut "$DESKTOP\Gang Chat.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0

  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "DisplayIcon" "$INSTDIR\${APP_EXE},0"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "NoRepair" 1
SectionEnd

Section "Uninstall"
  SetShellVarContext all

  Delete "$DESKTOP\Gang Chat.lnk"
  Delete "$SMPROGRAMS\Gang Chat\Gang Chat.lnk"
  Delete "$SMPROGRAMS\Gang Chat\Uninstall Gang Chat.lnk"
  RMDir "$SMPROGRAMS\Gang Chat"

  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat"

  RMDir /r "$INSTDIR"
SectionEnd
