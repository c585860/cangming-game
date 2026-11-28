#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <string>
#include <vector>

static bool file_exists(const std::wstring &p) {
    const DWORD attr = GetFileAttributesW(p.c_str());
    return attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

static bool dir_exists(const std::wstring &p) {
    const DWORD attr = GetFileAttributesW(p.c_str());
    return attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR cmd_line, int show_cmd) {
    wchar_t exe_buf[MAX_PATH * 4] = {};
    const DWORD n = GetModuleFileNameW(nullptr, exe_buf, static_cast<DWORD>(sizeof(exe_buf) / sizeof(exe_buf[0])));
    if (n == 0) {
        MessageBoxW(nullptr, L"无法定位启动器目录。", L"Cataclysm:EmperorCOOP 2.0", MB_OK | MB_ICONERROR);
        return 1;
    }

    std::wstring base_dir(exe_buf, n);
    const size_t slash = base_dir.find_last_of(L"\\/");
    if (slash != std::wstring::npos) {
        base_dir.resize(slash);
    }

    const std::wstring runtime_exe = base_dir + L"\\runtime\\godot_runtime.exe";
    const std::wstring main_pack   = base_dir + L"\\Cataclysm-EmperorCOOP2.0.pck";
    const std::wstring dll_gd      = base_dir + L"\\bin\\cangling.dll";
    const std::wstring dll_ccb     = base_dir + L"\\bin\\ccb_bridge.dll";
    const std::wstring ccb_data    = base_dir + L"\\ccb_data\\data";

    if (!file_exists(runtime_exe) || !file_exists(main_pack) || !file_exists(dll_gd) || !file_exists(dll_ccb) || !dir_exists(ccb_data)) {
        std::wstring msg = L"发行包缺少必要运行文件，请重新运行 tools\\build_release.ps1：\n\n";
        if (!file_exists(runtime_exe)) msg += L"- 缺少 runtime\\godot_runtime.exe\n";
        if (!file_exists(main_pack))   msg += L"- 缺少 Cataclysm-EmperorCOOP2.0.pck\n";
        if (!file_exists(dll_gd))      msg += L"- 缺少 bin\\cangling.dll\n";
        if (!file_exists(dll_ccb))     msg += L"- 缺少 bin\\ccb_bridge.dll\n";
        if (!dir_exists(ccb_data))     msg += L"- 缺少 ccb_data\\data\\\n";
        MessageBoxW(nullptr, msg.c_str(), L"Cataclysm:EmperorCOOP 2.0", MB_OK | MB_ICONERROR);
        return 2;
    }

    // Launch Godot runtime directly into Cataclysm-EmperorCOOP2.0.pck with working dir = release/ (zero console window)
    std::wstring args = L"\"" + runtime_exe + L"\" --main-pack \"" + main_pack + L"\"";
    if (cmd_line && cmd_line[0] != L'\0') {
        args += L" ";
        args += cmd_line;
    }

    std::vector<wchar_t> cmd_mut(args.begin(), args.end());
    cmd_mut.push_back(L'\0');

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = static_cast<WORD>(show_cmd);

    PROCESS_INFORMATION pi{};
    if (!CreateProcessW(
            runtime_exe.c_str(),
            cmd_mut.data(),
            nullptr,
            nullptr,
            FALSE,
            0,
            nullptr,
            base_dir.c_str(),
            &si,
            &pi)) {
        MessageBoxW(nullptr, L"启动游戏运行时失败，请确认杀毒软件未拦截 runtime\\godot_runtime.exe。", L"Cataclysm:EmperorCOOP 2.0", MB_OK | MB_ICONERROR);
        return 3;
    }

    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return 0;
}
