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
!define APP_ICON_FILE "GangChat.ico"
!define APP_SUPPORT_URL "https://ky-z.com/gang-chat/home/"

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
!include "LogicLib.nsh"
!include "nsDialogs.nsh"
!insertmacro GetTime
!insertmacro GetSize

!define MUI_ABORTWARNING
!define MUI_ICON "${PROJECT_ROOT}\windows\runner\resources\app_icon.ico"
!define MUI_UNICON "${PROJECT_ROOT}\windows\runner\resources\app_icon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "打开 Gang Chat"
!define MUI_WELCOMEPAGE_TITLE "欢迎安装 Gang Chat"
!define MUI_WELCOMEPAGE_TEXT "安装向导将引导你完成 Gang Chat 的安装。$\r$\n$\r$\n如果你正在更新，建议先关闭正在运行的 Gang Chat。点击“下一步”继续。"
!define MUI_DIRECTORYPAGE_TEXT_TOP "选择 Gang Chat 的安装位置。默认安装到 Program Files，适合所有用户使用。"
!define MUI_FINISHPAGE_TITLE "Gang Chat 已安装完成"
!define MUI_FINISHPAGE_TEXT "Setup 已完成 Gang Chat 的安装。"

!insertmacro MUI_PAGE_WELCOME
Page custom AppLanguagePage AppLanguagePageLeave
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "SimpChinese"

Var AppLanguage
Var LanguageZhHansRadio
Var LanguageZhHantRadio
Var LanguageEnglishRadio

Function .onInit
  StrCpy $AppLanguage "zh-Hans"
  InitPluginsDir
  File /oname=$PLUGINSDIR\gang_chat_language_preference.ps1 "${PROJECT_ROOT}\installer\windows\language_preference.ps1"
  Call ReadAppLanguagePreference
FunctionEnd

Function ReadAppLanguagePreference
  nsExec::ExecToStack 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\gang_chat_language_preference.ps1" -Mode Read'
  Pop $0
  Pop $1
  ${If} $0 == 0
    ${If} $1 == "zh-Hans"
    ${OrIf} $1 == "zh-Hant"
    ${OrIf} $1 == "en"
      StrCpy $AppLanguage $1
    ${EndIf}
  ${EndIf}
FunctionEnd

Function AppLanguagePage
  !insertmacro MUI_HEADER_TEXT "选择显示语言" "安装完成后 Gang Chat 将默认使用这个语言。"

  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == error
    Abort
  ${EndIf}

  ${NSD_CreateLabel} 0 0 100% 28u "Setup 会优先沿用旧版本的语言设置；如果没有旧版本设置，则默认使用简体中文。"
  Pop $0
  ${NSD_CreateRadioButton} 0 44u 100% 12u "简体中文"
  Pop $LanguageZhHansRadio
  ${NSD_CreateRadioButton} 0 66u 100% 12u "繁體中文"
  Pop $LanguageZhHantRadio
  ${NSD_CreateRadioButton} 0 88u 100% 12u "English"
  Pop $LanguageEnglishRadio

  ${If} $AppLanguage == "zh-Hant"
    ${NSD_Check} $LanguageZhHantRadio
  ${ElseIf} $AppLanguage == "en"
    ${NSD_Check} $LanguageEnglishRadio
  ${Else}
    ${NSD_Check} $LanguageZhHansRadio
  ${EndIf}

  nsDialogs::Show
FunctionEnd

Function AppLanguagePageLeave
  ${NSD_GetState} $LanguageZhHantRadio $0
  ${If} $0 == ${BST_CHECKED}
    StrCpy $AppLanguage "zh-Hant"
    Return
  ${EndIf}

  ${NSD_GetState} $LanguageEnglishRadio $0
  ${If} $0 == ${BST_CHECKED}
    StrCpy $AppLanguage "en"
    Return
  ${EndIf}

  StrCpy $AppLanguage "zh-Hans"
FunctionEnd

Function WriteAppLanguagePreference
  ${If} $AppLanguage != "zh-Hant"
  ${AndIf} $AppLanguage != "en"
    StrCpy $AppLanguage "zh-Hans"
  ${EndIf}

  nsExec::ExecToLog 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\gang_chat_language_preference.ps1" -Mode Write -Language "$AppLanguage"'
  Pop $1
  ${If} $1 != 0
    DetailPrint "Unable to save Gang Chat language preference ($1)."
  ${EndIf}
FunctionEnd

Function CleanInstallDirectory
  ${If} $INSTDIR == ""
    Abort "安装目录为空，无法继续安装。"
  ${EndIf}

  IfFileExists "$INSTDIR\${APP_EXE}" 0 done
  DetailPrint "Cleaning old Gang Chat files from $INSTDIR"
  RMDir /r "$INSTDIR"

done:
FunctionEnd

Section "Install"
  Call CleanInstallDirectory
  SetOutPath "$INSTDIR"
  File /r "${SOURCE_DIR}\*.*"
  File /oname=${APP_ICON_FILE} "${PROJECT_ROOT}\windows\runner\resources\app_icon.ico"
  ${GetTime} "" "L" $0 $1 $2 $3 $4 $5 $6
  FileOpen $7 "$INSTDIR\gang_chat_install_info.txt" w
  FileWrite $7 "$2/$1/$0"
  FileClose $7

  Call WriteAppLanguagePreference

  SetShellVarContext all
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2

  CreateDirectory "$SMPROGRAMS\Gang Chat"
  CreateShortcut "$SMPROGRAMS\Gang Chat\Gang Chat.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_ICON_FILE}" 0
  CreateShortcut "$SMPROGRAMS\Gang Chat\Uninstall Gang Chat.lnk" "$INSTDIR\Uninstall.exe" "" "$INSTDIR\${APP_ICON_FILE}" 0
  CreateShortcut "$DESKTOP\Gang Chat.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_ICON_FILE}" 0

  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "DisplayIcon" "$INSTDIR\${APP_ICON_FILE},0"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "HelpLink" "${APP_SUPPORT_URL}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "URLInfoAbout" "${APP_SUPPORT_URL}"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gang Chat" "EstimatedSize" $0
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
