Function pause ($message)
{
    # Check if running Powershell ISE
    if ($psISE)
    {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show("$message")
    }
    else
    {
        Write-Host "$message" -ForegroundColor Yellow
        $x = $host.ui.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}


[Byte[]] $key = (1..16)
$password2 = Get-Content C:\Script\Equallogic\sec_lacal| ConvertTo-SecureString -Key $key
$username2 = "localhost\PSuser"
$credential2 = New-Object System.Management.Automation.PSCredential($username2,$password2)

$scriptblock = {C:\Windows\system32\subst.exe}
$mapeo_actual = Invoke-Command -scriptblock $scriptblock 
$mapeo_actual = $mapeo_actual | Where-Object {$_ -like "F:\*"}
$Cliente_name = Read-Host -Prompt "Ingrese el nombre del cliente"

$session =  New-PSSession  -Credential $credential2 -Name "NewSession" -ComputerName $Env:COMPUTERNAME 
$return_path = invoke-command -session $session -FilePath "C:\Script\Equallogic\connect-presentacion.ps1" -ArgumentList $Cliente_name, $mapeo_actual 


if ($return_path){
    subst F: /D
    subst F: ($return_path | Select-Object -Last 1)
    Invoke-Item F:\
}

pause "Script terminado, precione cualquier tecla para salir."


