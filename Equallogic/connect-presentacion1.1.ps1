<#
        .Synopsis
           Ver: 1.1 - Conecta presentación de cliente
        .DESCRIPTION
           Conecta un snapshot generado automaticamente por una tarea programada
        .EXAMPLE
           connect-presentación.ps1 -Clientename [nom_cliente]
        .EXAMPLE
           Otro ejemplo de cómo usar este cmdlet
        #>


[CmdletBinding()]
Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string]$Clientename,
   [Parameter(Mandatory=$false,Position=2)]
   [string]$var_subst
)

#Agrega set de herramientas para discos dinámicos
. "C:\Script\Equallogic\Disk-Function.ps1"

$ErrorActionPreference = "Stop"
Import-Module "C:\Program Files\EqualLogic\bin\EqlPSTools.dll"

$MensajeInicio = @"
***************************************************************
Versión 1.1
Novedades:
    -Permite usar discos dinámicos.
    -Deja registros en el Visor de eventos.
    -Mejoras en el modo Verbose
    -Mejora en el rendimiento
    -Avisa si existe inconsistencia entre el cliente y el mapeo 

***************************************************************
"@

Write-Host $MensajeInicio -ForegroundColor Magenta


function ErrorMan
{
    param( [parameter(Mandatory=$True)][string]$Mensaje)
    $smtp = "192.168.3.2" 
    $to = "tomas.cribb@neuralsoft.com"
    $from = "informes@neuralsoft.com" 
    $subject = "Error en PresentacionesDiarias.ps1"

    $Evento = "Error al intentar mapear. Usuario $env:USERNAME, Disco $VolumeName, Cliente $Clientename. "
    $Evento += $Mensaje

    Write-EventLog -LogName "Application" -Source "PresentacionesDiarias" -EventID 3011 -EntryType Error -Message $Evento  -Category 1 -RawData 10,20

    #send-MailMessage -SmtpServer $smtp -To $to -From $from -Subject $subject -Body $Mensaje -BodyAsHtml -Priority high -Encoding Unicode
    #sleep 5

    return "Error"
}



function ClienteIsValid ($nom_cliente)
{
    try{
        $nom_cliente = $nom_cliente + ".neuralsoft.com.ar"
        Resolve-DnsName $nom_cliente
    }catch{
        
        return $false
    }
    return $True
}


$valido = ClienteIsValid $Clientename

while (-not ($valido))
{
    Write-Host "El cliente ingresado no es válido!" -ForegroundColor Red
    $Clientename = Read-Host -Prompt "Ingrese el nombre del cliente o Q para salir." 
    if($Clientename -eq "q"){
        Write-Host "Saliendo..." -ForegroundColor Green 
        sleep 2 
        exit
    }else{
        $valido = ClienteIsValid $Clientename
    }
}

$Clientename = $Clientename + ".neuralsoft.com.ar"
$RegistroDNS = Resolve-DnsName $Clientename

if (-not $var_subst){
    $scriptblock = {C:\Windows\system32\subst.exe}
    $mapeo_actual = Invoke-Command -scriptblock $scriptblock 
    $mapeo_actual = $mapeo_actual | Where-Object {$_ -like "F:\*"}
}else{
    $mapeo_actual = $var_subst
}


if ($mapeo_actual){
    Write-Host "Existe un mapeo actualmente:" -ForegroundColor DarkRed
    Write-Host $mapeo_actual -ForegroundColor Red
    Write-Host ""
    $continua = Read-Host "Desea continuar (Y/N)" 
    while ($continua.ToUpper() -ne 'Y' -and $continua.ToUpper() -ne 'N' ){
        $continua = Read-Host - "Desea continuar (Y/N)"
    }
    Switch ($continua){
        Y {Write-Host "Mapeando nueva unidad..." -ForegroundColor Green
        $scriptblock = { C:\Windows\system32\subst.exe F: /D}
        Invoke-Command -scriptblock $scriptblock 
        
        }
        N {Write-Host "Saliendo..." -ForegroundColor Green; sleep 2; exit}
    }
}



try{
[Byte[]] $key = (1..16)
$password = Get-Content C:\Script\Equallogic\sec_eql | ConvertTo-SecureString -Key $key
$username = "grpadmin"
$credential = New-Object System.Management.Automation.PSCredential($username,$password)
$AccessPath = "C:\Servidores2\"
}catch{
    Write-Host "No se pudo cargar las credenciales."
    ErrorMan $Error[0]
    Break
}





try{
    $reference = Import-Csv  "C:\Script\Equallogic\referencias.cvs" -ErrorAction Stop
}
catch{
    Write-Host "No se pudo cargar el archivo de referencias, no se puede continuar" -ForegroundColor Red
    ErrorMan $error[0]
    Break
}




If ($RegistroDNS.NameHost -match "^nevermind0\d{1,3}\.neuralsoft\.com\.ar"){
    $NumServer = $RegistroDNS.NameHost -replace '(^nevermind0)(\d{1,3})(\.neuralsoft\.com\.ar)','$2'
    $VolumeName = "NV0" + $NumServer + "-F"
}else{
    Write-Host "No se encontro servidor para el cliente $Clientename" -ForegroundColor Red
    ErrorMan "No se encontro servidor para el cliente $Clientename"
    Break
}

#Variable para las salida de las invocaciones de comandos externos, escrivir con -Vervoce
$Func_Salida =""
$AccessPath+=$VolumeName

if (-not (Test-Path "$AccessPath\Clientes")){

    Write-Host "Preparando conexión a la SAN..." -ForegroundColor Green
    #Desconecto los grupos
    $Func_Salida = Get-EqlGroup | Disconnect-EqlGroup 

    try{
    $DataConn = $reference | Where-Object {$_.VolumeName -eq $VolumeName}
    if (-not $DataConn){
        Write-Host "No se encontro el snapshot en referencia, consulte con Infraestructura..." -ForegroundColor Green
        sleep 2
        exit
       }
    $Func_Salida = Connect-EqlGroup  -GroupName $DataConn.GroupName -GroupAddress $DataConn.GroupAddress -Credential $credential -IgnoreSavedCredentials
    Write-Host "Obteniendo Snapshot..." -ForegroundColor Green
    $SnapToConnect = Get-EqlSnapshot -VolumeName $DataConn.VolumeName | Where-Object {$_.SnapshotDescription -eq "PresDiaria"} 
    #Si el snapshot esta online en la SAN interpreto que está mapeado.
    if ($SnapToConnect.IsOnline -eq $false){
        Write-Host "Cambiando estado a OnLine..." -ForegroundColor Green
        $Func_Salida = $SnapToConnect | Set-EqlSnapshot -OnlineStatus online
        Write-Host "Actualizando destinos iSCSI..." -ForegroundColor Green
        $Conn = Get-IscsiConnection
        $Conn[0] | Update-IscsiTarget
        Write-Host "Conectando a destino iSCSI..." -ForegroundColor Green
        $iSCSI_Conn = Connect-IscsiTarget -NodeAddress $DataConn.SnapshotName 
        $iSCSI_Conn = $iSCSI_Conn | Select-Object -First 1
        sleep 5
    }else{
        #El snapshot es ta OnLine en la SAN pero desconectado, lo conecto.
        $iSCSI_Conn = Get-IscsiSession | Where-Object {$_.TargetNodeAddress -eq $DataConn.SnapshotName} 
        if(-not $iSCSI_Conn){
            $Conn = Get-IscsiConnection
            $Conn[0] | Update-IscsiTarget
            Write-Host "Conectando a destino iSCSI..." -ForegroundColor Green
            $iSCSI_Conn = Connect-IscsiTarget -NodeAddress $DataConn.SnapshotName 
            $iSCSI_Conn = $iSCSI_Conn | Select-Object -First 1
            sleep 5
        }
        
        if (($iSCSI_Conn.isConnected) -eq $false){
            $Conn = Get-IscsiConnection
            $Conn[0] | Update-IscsiTarget
            Write-Host "Conectando a destino iSCSI..." -ForegroundColor Green
            $iSCSI_Conn = Connect-IscsiTarget -NodeAddress $DataConn.SnapshotName
            $iSCSI_Conn = $iSCSI_Conn | Select-Object -First 1
        }
        $iSCSI_Conn = $iSCSI_Conn | Select-Object -First 1
    }

        if(-not $iSCSI_Conn){
            Write-Host "No se pudo conectar el snapshot al servidor, solicite la presentación a Infraestrutura" -ForegroundColor Red
            ErrorMan $error[0]
            Break    
        }

        Write-Host "Identificando disco (Esto puede tardar varios minutos)..." -ForegroundColor Green
        $Disk_ID = ""
        $Disk_ID = $iSCSI_Conn | Get-Disk

        if(-not $Disk_ID){
            Write-Host "No se pudo obtener el disco, solicite la presentación a Infraestrutura" -ForegroundColor Red
            ErrorMan $error[0]
            Break
        }

        Write-Host "Cambiando ID del disco ..." -ForegroundColor Green
        Write-Verbose ("Disco Nro: " + [string]$Disk_ID[0].Number)
        ChangeDiskID $Disk_ID[0]
        #Write-Verbose $Func_Salida

        Write-Host "Preparando disco..." -ForegroundColor Green
        Write-Verbose ("Disco Nro: " + [string]$Disk_ID[0].Number)
        Set-DiskOnline $Disk_ID[0].Number
        #Write-Verbose $Func_Salida
        
        Write-Host "Obteniendo estado del disco..." -ForegroundColor Green
        Write-Verbose ("Disco Nro: " + [string]$Disk_ID[0].Number)
        $Disk_Info = get-DiskInfo $Disk_ID[0].Number
        Write-Verbose ("Volumen Nro: " + [string]$Disk_Info[0].NumVolume)
        Write-Verbose ("Etiqueta Actual: " + [string]$Disk_Info[0].Etiqueta)
        Write-Verbose ("File System: " + [string]$Disk_Info[0].Fs)
        Write-Verbose ("Tipo: " + [string]$Disk_Info[0].Tipo)
        Write-Verbose ("Tamaño: " + [string]$Disk_Info[0].Tamano)
        Write-Verbose ("Estado: " + [string]$Disk_Info[0].Estado)

        if($Disk_Info -eq ""){
            
            $err_mensaje = "Existe un problema con el snapshot y no se puede presentar, consulte con Infraesturctura! "
            $err_mensaje += ("Disco Nro: " + [string]$Disk_ID[0]) 
            
            Write-Host $err_mensaje -ForegroundColor Red
            ErrorMan $err_mensaje
            Break
        }

        switch ($Disk_Info.Tipo)
        {
            'Simple' {Write-Host "El disco en Dinámico." -ForegroundColor Yellow}
            'Particin' {Write-Host "El disco en Básico." -ForegroundColor Yellow}
            Default {Write-Host "No se pudo identificar el tipo de disco." -ForegroundColor Yellow       
                    ErrorMan $error[0]
                    Break
                    }
        }

        ################
        Write-Host "Verificando destino de montaje..." -ForegroundColor Green
        if (Test-Path $AccessPath){
            $Item = Get-Item $AccessPath
            Switch ($Item.Attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Directory)) {
                ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Directory) {
                    # Is reparse directory / symlink
                    If ($whatif) {
                        Write-Host "What if: Performing the operation `"Delete Directory`" on target `"$($_.FullName)`""
                    } Else {
                        [System.IO.Directory]::Delete($Item.FullName);
                        Break;
                    }
                }
                ([IO.FileAttributes]::ReparsePoint -bor 0) {
                    # Is reparse file / hardlink
                    If ($whatif) {
                        Write-Host "What if: Performing the operation `"Delete File`" on target `"$($_.FullName)`""
                    } Else {
                        [System.IO.File]::Delete($Item.FullName);
                        Break;
                    }
                }
                default {
                    Remove-Item $Item.FullName
                    
                }
            }
            $new_snapshot = New-Item -Path $AccessPath -Type directory
            
        }else{
            $new_snapshot = New-Item -Path $AccessPath -Type directory
        }

        #################

        Write-Host "Montando el Disco..." -ForegroundColor Green
        Write-Verbose ("$Disk_ID[0] $Disk_Info  $Disk_Info $AccessPath")
        Mount-Disk $Disk_ID[0].Number $Disk_Info.NumVolume  $Disk_Info.ltr $AccessPath
        sleep 2

    
        if (Test-Path "$AccessPath\Clientes"){
            label.exe /MP $AccessPath  $VolumeName
        }else{
            Write-Host "No se pudo montar el disco, solicite la presentación a Infraestrutura" -ForegroundColor Red
            ErrorMan $error[0]
            Break
        }
    
        #VER TEMA DISCOS DINAMICOS
        #$Volume_ID = Get-Disk $Disk_ID.Number | Get-Partition | Get-Volume 
        #if (-not (Test-Path $AccessPath)){
        #    New-Item -Path $AccessPath -Type directory
        #    Add-PartitionAccessPath -DiskNumber $Disk_ID.Number -PartitionNumber $Particiones[0].PartitionNumber -AccessPath $AccessPath
        #    Remove-PartitionAccessPath -DiskNumber $Disk_ID.Number -PartitionNumber $Particiones[0].PartitionNumber -AccessPath ((get-disk $Disk_ID.Number | Get-Partition).DriveLetter + ":")
        #}

    }catch{
        Write-Host "No se pudo conectar al storage, contacte a Infraestructura." -ForegroundColor Red
        ErrorMan $error[0]
        Break
    }

}else{
    Write-Host "El snapshot se encuentra mapeado, se utilizará el mapeo existente..." -ForegroundColor Green
}


$scriptblock = {C:\Windows\system32\subst.exe F: $AccessPath}
Invoke-Command -scriptblock $scriptblock 



if (Test-Path ("$AccessPath\Clientes\" + ($Clientename.Split('.')[0]))){
            Write-EventLog -LogName "Application" -Source "PresentacionesDiarias" -EventID 3010 -EntryType Information -Message "El usuario $env:USERNAME mapeó correctamente el disco $VolumeName del Cliente $Clientename" -Category 1 -RawData 10,20
            Write-Verbose "CORRECTO!!! Se corresponde el Usuario con el Mapeo" 
            Write-Host "Disco mapeado en: " -ForegroundColor Yellow
            Write-Host $AccessPath -ForegroundColor Yellow
            return $AccessPath
        }else{
            Write-Host "ERROR!!! El mapeo de realizó pero NO existe una carpeta con el nombre del cliente ingresado, por favor consulte a Infraestructura." -ForegroundColor Red
            ErrorMan "ERROR!!! El mapeo de realizó pero NO existe una carpeta con el nombre del cliente ingresado, por favor consulte a Infraestructura."
            return "Error"
            Break
        }
    



#sleep -Seconds 5
