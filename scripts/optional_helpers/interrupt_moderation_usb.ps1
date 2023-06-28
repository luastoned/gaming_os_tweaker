<#
	WIP (not done)

	It's not done for Intel nor AMD, for AMD I dont have any information about it, to know if it's the same address space value and if it's the 24h value to sum with it.
	For Intel, there are cases not addressed by docs in links below, so unless someone who understand the domain provide a fix or complete information, it will stay unfinished.
	How do I know that the value will always be in the same 18hex place, unless that is complete accurate/correct, this part could also be wrong.

	-------------------------

	Automated script to disable interrupt moderation / coalesting in all usb controllers

	https://www.overclock.net/threads/usb-polling-precision.1550666/page-61
	https://github.com/djdallmann/GamingPCSetup/tree/master/CONTENT/RESEARCH/PERIPHERALS#universal-serial-bus-usb
	https://github.com/BoringBoredom/PC-Optimization-Hub/blob/main/content/xhci%20imod/xhci%20imod.md
	https://linustechtips.com/topic/1477802-what-does-changing-driver-interrupt-affinity-cause-the-driver-to-do/

	Note1: RW command will not run if you have the GUI version open.
	Note2: You should be able to run this script from anywhere as long as you have downloaded the gaming_os_tweaks folder.

	-------------------------

	In case you get problems running the script in Win11, you can run the command to allow, and after, another to set back to a safer or undefined policy

	You can check the current policy settings
	Get-ExecutionPolicy -List

	Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Confirm:$false -Force
	Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope CurrentUser -Confirm:$false -Force
#>

# Start as administrator
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
	Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit
}

# Startup command is optional, because before that you must test the script if will work and not cause BSOD, by not having the startup set, a simple restart should be enough to have it normalized.
# If you want to execute startup script, change from $false to $true
$enableApplyStartupScript = $false
$taskName = "InterruptModerationUsb"
$taskExists = Get-ScheduledTask | Where-Object {$_.TaskName -like $taskName }
if (!$taskExists -And $enableApplyStartupScript) {
  $action = New-ScheduledTaskAction -Execute "powershell" -Argument "-WindowStyle hidden -ExecutionPolicy Bypass -File $PSScriptRoot\interrupt_moderation_usb.ps1"
	$delay = New-TimeSpan -Seconds 10
	$trigger = New-ScheduledTaskTrigger -AtLogOn -RandomDelay $delay
	$principal = New-ScheduledTaskPrincipal -UserID "LOCALSERVICE" -RunLevel Highest
	Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal
	[Environment]::NewLine

	# In case you have to remove the script from startup, but are not able to do from the UI, run:
	# Unregister-ScheduledTask -TaskName "InterruptModerationUsb"
}

Write-Host "Started disabling interrupt moderation in all usb controllers"
[Environment]::NewLine

Remove-Item -Path "HKCU:\SOFTWARE\RW-Everything" -Recurse -ErrorAction Ignore

# REGs improve tools compatibility with Win11 - You might need to reboot to take effect
$BuildNumber = Get-WMIObject Win32_OperatingSystem | Select -ExpandProperty BuildNumber
if ($BuildNumber -ge 22000) {
	Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name "Enabled" -Value 0 -Force -Type Dword -ErrorAction Ignore
	Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios" -Name "HypervisorEnforcedCodeIntegrity" -Value 0 -Force -Type Dword -ErrorAction Ignore
	Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" -Name "EnableVirtualizationBasedSecurity" -Value 0 -Force -Type Dword -ErrorAction Ignore
	Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\SystemGuard" -Name "Enabled" -Value 0 -Force -Type Dword -ErrorAction Ignore
	Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config" -Name "VulnerableDriverBlocklistEnable" -Value 0 -Force -Type Dword -ErrorAction Ignore
}

$tempMemDumpFileName = "TEMP_MEM_DUMP"
$RWPath = "$(Split-Path -Path $PSScriptRoot -Parent)\tools\RW"

[PsObject[]]$USBControllersAddresses = @()

$allUSBControllers = Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.Name -match 'USB' -and $_.Name -match 'Controller' -and $_.Name -match 'Extensible'  } | Select-Object -Property Name, DeviceID
foreach ($usbController in $allUSBControllers) {
	$allocatedResource = Get-CimInstance -ClassName Win32_PNPAllocatedResource | Where-Object { $_.Dependent.DeviceID -like "*$($usbController.DeviceID)*" } | Select @{N="StartingAddress";E={$_.Antecedent.StartingAddress}}
	$deviceMemory = Get-CimInstance -ClassName Win32_DeviceMemoryAddress | Where-Object { $_.StartingAddress -eq "$($allocatedResource.StartingAddress)" }

	$deviceProperties = Get-PnpDeviceProperty -InstanceId $usbController.DeviceID
	$locationInfo = $deviceProperties | Where KeyName -eq 'DEVPKEY_Device_LocationInfo' | Select -ExpandProperty Data
	$PDOName = $deviceProperties | Where KeyName -eq 'DEVPKEY_Device_PDOName' | Select -ExpandProperty Data

	if ([string]::IsNullOrWhiteSpace($deviceMemory.Name)) {
		continue
	}

	$USBControllersAddresses += [PsObject]@{
		Name = $usbController.Name
		DeviceId = $usbController.DeviceID
		MemoryRange = $deviceMemory.Name
		LocationInfo = $locationInfo
		PDOName = $PDOName
	}
}

function Convert-Decimal-To-Hex {
	param ([int64] $value)
	return '0x' + [System.Convert]::ToString($value, 16).ToUpper()
}

function Convert-Hex-To-Decimal {
	param ([string] $value)
	return [convert]::toint64($value, 16)
}

function Stop-Tool-And-Clean-Temp-Files {
	Stop-Process -Name Rw.exe -Force -ErrorAction Ignore
	Remove-Item -Path $RWPath\$tempMemDumpFileName*
}

function Get-Left-Side-From-MemoryRange {
	param ([string] $memoryRange)
	return $memoryRange.Split("-")[0]
}

function Get-VendorId-From-DeviceId {
	param ([string] $deviceId)
	if ([string]::IsNullOrWhiteSpace($deviceId)) {
		return "None"
	}
	$deviceIdMinInfo = $deviceId.Split("\")[1].Split("&")
	$deviceIdVENValue = $deviceIdMinInfo[0].Split("_")[1]
	$deviceIdDEVValue = $deviceIdMinInfo[1].Split("_")[1]
	return "0x" + $deviceIdDEVValue + $deviceIdVENValue
}

function Build-Filename {
	param ([string] $memoryRange)
	$LeftSideMemoryRange = Get-Left-Side-From-MemoryRange -memoryRange $memoryRange
	return "$tempMemDumpFileName-$LeftSideMemoryRange"
}

function Dump-Memory-File {
	param ([string] $memoryRange)
	$LeftSideMemoryRange = Get-Left-Side-From-MemoryRange -memoryRange $memoryRange
	$fileName = Build-Filename -memoryRange $memoryRange
	& "$RWPath\Rw.exe" /Min /NoLogo /Stdout /Stderr /Command="DMEM $LeftSideMemoryRange 256 $RWPath\$fileName" | Out-Null
	while (!(Test-Path -Path $RWPath\$fileName)) { Start-Sleep -Seconds 1 }
}

function Disable-IMOD {
	param ([string] $address)
	& "$RWPath\Rw.exe" /Min /NoLogo /Stdout /Stderr /Command="W32 $address 0x00000000"
	Start-Sleep -Seconds 1
}

function Build-Address {
	param ([string] $memoryRange)
	$fileName = Build-Filename -memoryRange $memoryRange
	$selectedValues = (Get-Content -Path "$RWPath\$fileName" -Wait | Select -Index 3).Split(" ")
	$eighteenPositionValue = '0x' + $selectedValues[4] + $selectedValues[3]
	$LeftSideMemoryRange = Get-Left-Side-From-MemoryRange -memoryRange $memoryRange
	$BaseAddress = Convert-Hex-To-Decimal -value $LeftSideMemoryRange
	$BaseAddressOffset = Convert-Hex-To-Decimal -value $eighteenPositionValue
	$TwentyFourHexInDecimal = Convert-Hex-To-Decimal -value '0x24'
	$AddressInDecimal = $BaseAddress + $BaseAddressOffset + $TwentyFourHexInDecimal
	return Convert-Decimal-To-Hex -value $AddressInDecimal
}

foreach ($item in $USBControllersAddresses) {
	Dump-Memory-File -memoryRange $item.MemoryRange

	$Address = Build-Address -memoryRange $item.MemoryRange
	if ([string]::IsNullOrWhiteSpace($Address)) {
		Write-Host "Address is empty, didnt found any valid to disable IMOD"
		continue
	}
	Disable-IMOD -address $Address

	$VendorId = Get-VendorId-From-DeviceId -deviceId $item.DeviceId
	Write-Host "Device: $($item.Name)"
	Write-Host "Device ID: $($item.DeviceId)"
	Write-Host "Location Info: $($item.LocationInfo)"
	Write-Host "PDO Name: $($item.PDOName)"
	Write-Host "Vendor ID: $VendorId"
	Write-Host "Memory Range: $($item.MemoryRange)"
	Write-Host "Address Used: $Address"
	[Environment]::NewLine
}

Stop-Tool-And-Clean-Temp-Files

cmd /c pause
