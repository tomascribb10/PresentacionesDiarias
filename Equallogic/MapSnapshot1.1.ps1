<#
        .Synopsis
           Ver: 1.1 - Lanzador de connect-presentación para usuario sin permisos de admin
        .DESCRIPTION
           Descripción larga
        .EXAMPLE
           Ejemplo de cómo usar este cmdlet
        .EXAMPLE
           Otro ejemplo de cómo usar este cmdlet
        #>

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
        Write-Host "$message" -ForegroundColor Green
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
$return_path = invoke-command -session $session -FilePath "C:\Script\Equallogic\connect-presentacion1.1.ps1" -ArgumentList $Cliente_name, $mapeo_actual 


#El script connect-presentacion2.ps1 devuelve el path o el string "Error"
if ($return_path -ne "Error"){
    subst F: /D
    subst F: ($return_path | Select-Object -Last 1)
    Invoke-Item F:\
    Write-EventLog -LogName "Application" -Source "PresentacionesDiarias" -EventID 3020 -EntryType Information -Message "El usuario $env:USERNAME mapeó correctamente el disco $return_path del Cliente $Cliente_name" -Category 1 -RawData 10,20
}else{
    Write-Host "Algo anduvo mal, consulte con Infraestructura." -ForegroundColor Red
}

pause "Script terminado, precione cualquier tecla para salir."
