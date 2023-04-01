:: Fix Valorant for previously disabled mitigations
for %%a in (valorant valorant-win64-shipping vgtray vgc) do (
    powershell -NoP -C "Set-ProcessMitigation -Name %%a.exe -Enable CFG"
    powershell -NoP -C "Set-ProcessMitigation -Name %%a.exe -Enable SEHOP"
    powershell -NoP -C "Set-ProcessMitigation -Name %%a.exe -Enable DEP"
    powershell -NoP -C "Set-ProcessMitigation -Name %%a.exe -Enable EmulateAtlThunks"
)

:: Changes above might be enough
:: bcdedit /set nx AlwaysOn
:: REG DELETE "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v FeatureSettingsOverride /f
:: REG DELETE "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v FeatureSettingsOverrideMask /f
:: REG DELETE "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v EnableCfg /f
:: REG DELETE "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\kernel" /v DisableExceptionChainValidation /f
:: REG DELETE "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\kernel" /v KernelSEHOPEnabled /f
:: REG DELETE "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v MitigationOptions /f
:: REG DELETE "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v MitigationAuditOptions /f
:: REG DELETE "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager" /v ProtectionMode /f
:: REG ADD "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v MoveImages /t REG_DWORD /d 1 /f