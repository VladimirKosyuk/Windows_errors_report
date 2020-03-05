﻿#Отправляет список ошибок по почте за последний месяц из eventlog для серверов домена
#
# ДАТА: 05 марта 2020 года										   
 
#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#Для успешного выполнения скрипта необходимо:
<# 

Powersheel версии 4
Powersheel ExecutionPolicy Unrestricted
Allow WinRM
ActiveDirectory module

#>
#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#Порядок выполнения скрипта: 
<# 
-Считывает конфиг с переменными, должен находиться в той-же папке, что и скрипт
-Формирует список тех серверов, объекты которых включены, обращались к DC не более 14 дней назад, OU которых содержит Servers и не Test
-Для каждого из полученных серверов по WinRM получить список список ошибок
-Если для сервера не получены значения  в течении  5 минут - продолжить с другим сервером
-Если во время сбора данных получены ошибки - вывод в log файл
-Получить значения, посчитать количество повторяющихся, записать информацию в csv файл
-Отправить письмо без авторизации с результатами выполнения
#>
#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------



$confg = "$PSScriptRoot\GetWinEvents"+('.txt')
$globallog = "$PSScriptRoot\GetWinEvents"+('.log')

try

{
    $values = (Get-Content $confg).Replace( '\', '\\') | ConvertFrom-StringData 
    $To = $values.To
    $SmtpServer = $values.SmtpServer
    $SmtpPort = $values.SmtpPort
    $SmtpDomain = $values.SmtpDomain
    $Output = $values.Output
  
}

catch

{   
    Write-Host "No config file has been found" -ForegroundColor RED
    Write-Output $Error[0].Exception.Message
    Write-Host "Script terminated with error." -ForegroundColor Yellow
    Write-Output ("FATAL ERROR - Config file is accessible check not passed  "+(Get-Date)) | Out-File "$globallog" -Append
    Break 
}


$Date = Get-Date -Format "MM.dd.yyyy"
$Unic = Get-WmiObject -Class Win32_ComputerSystem |Select-Object -ExpandProperty "Domain"
$list = Get-ADComputer -Filter * -properties *|Where-Object {$_.enabled -eq $true} | Where-Object {(($_.distinguishedname -like "*Servers*") -and ($_.distinguishedname -notlike "*Test*")) -and ($_.LastLogonDate -ge ((Get-Date).AddDays(-14)))}| Select-Object -ExpandProperty "name"


foreach ($pc in $list) {
$error.Clear()
$Events = Invoke-Command -ComputerName $pc -ScriptBlock {
$VerbosePreference='Continue'
Get-EventLog -LogName System -After (Get-Date).AddMonths(-1) |
? { $_.entryType -Match "Error" -and "Critical" } |
Group-Object -Property EventID |
% { $_.Group[0] | Add-Member -PassThru -MemberType NoteProperty -Name Count -Value $_.Count }|
Select-Object MachineName, EventID, Count, Message

} -AsJob
Wait-Job $Events -Timeout 300
if ($Events.State -eq 'Completed') {
$Events |select State, Location, PSBeginTime, PSEndTime| Out-File $Output\$Unic"_"$Date"_"events_SCRdebug.log -Append
} 
    else {
  $Events |select State, Location, PSBeginTime, PSEndTime|  Out-File $Output\$Unic"_"$Date"_"events_SCRdebug.log -Append
  Stop-Job -Id $Events.Id
} 
Receive-Job $Events 4>&1| Select-Object -Property * -ExcludeProperty PSComputerName,RunspaceID, PSShowComputerName |Export-Csv -Append -Delimiter ';' -Path $Output\$Unic"_"$Date"_"events.csv -Encoding UTF8 -NoTypeInformation
$error | Out-File $Output\$Unic"_"$Date"_"events_SCRerrors.log -Append
}

$RunState = @(Get-Content $Output\$Unic"_"$Date"_"events_SCRdebug.log |  Where-Object { $_.Contains("Running") } ).Count
$CompleteState = @(Get-Content $Output\$Unic"_"$Date"_"events_SCRdebug.log |  Where-Object { $_.Contains("Completed") } ).Count
$FailedState = @(Get-Content $Output\$Unic"_"$Date"_"events_SCRdebug.log |  Where-Object { $_.Contains("Failed") } ).Count

$From = (Get-WmiObject -Class Win32_ComputerSystem |Select-Object -ExpandProperty "name")+"@"+$SmtpDomain
$Attachments = (get-childitem $Output\$Unic"_"$Date"_events"*.*).fullname
$Subject = $Unic+" servers: errors and critical events last month"
$Body = "Proceed "+($list.count)+" servers, Completed "+($CompleteState)+", Failed "+($RunState+$FailedState)

Send-MailMessage -To $To -From $From -Subject $Subject -Body $Body -Attachments $Attachments -Port $SmtpPort -SmtpServer $SmtpServer

Remove-Variable -Name * -Force -ErrorAction SilentlyContinue

