[CmdletBinding()]
Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string]$Clientename,
   [Parameter(Mandatory=$false,Position=2)]
   [string]$var_subst
)

$ErrorActionPreference = "Stop"
Import-Module "C:\Program Files\EqualLogic\bin\EqlPSTools.dll"

function ErrorMan
{
    param( [parameter(Mandatory=$True)][string]$Mensaje)
    $smtp = "192.168.3.2" 
    $to = "tomas.cribb@neuralsoft.com"
    $from = "informes@neuralsoft.com" 
    $subject = "Error en PresentacionesDiarias.ps1"

    send-MailMessage -SmtpServer $smtp -To $to -From $from -Subject $subject -Body $Mensaje -BodyAsHtml -Priority high -Encoding Unicode
    sleep 5
}

function ChangeDiskID
{
    param( [parameter(Mandatory=$True)][System.Object]$Disk_obj)
    #$guid = [GUID]::NewGuid()
    $guid = Get-Random -Minimum 111111111 -Maximum 999999999
    $guid = "{0:X0}" -f $guid
    $uniqueIds = $Disk_obj

    ForEach ($uniqueId in $uniqueIds)
    {
    
        $disknumber = $uniqueId.Number
        $cmds = "`"SELECT DISK $disknumber`"",           
                "`"UNIQUEID DISK ID=$guid`""          
        $scriptblock = [string]::Join(",",$cmds)
        $diskpart =$ExecutionContext.InvokeCommand.NewScriptBlock("$scriptblock | DISKPART")        
        Invoke-Command  -ScriptBlock $diskpart
    
    }
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



Write-Host "Preparando conexión a la SAN..." -ForegroundColor Green
#Desconecto los grupos
Get-EqlGroup | Disconnect-EqlGroup 

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

$AccessPath+=$VolumeName

try{
$DataConn = $reference | Where-Object {$_.VolumeName -eq $VolumeName}
if (-not $DataConn){
    Write-Host "No se encontro el snapshot en referencia, consulte con Infraestructura..." -ForegroundColor Green
    sleep 2
    exit
   }
Connect-EqlGroup  -GroupName $DataConn.GroupName -GroupAddress $DataConn.GroupAddress -Credential $credential -IgnoreSavedCredentials
Write-Host "Obteniendo Snapshot..." -ForegroundColor Green
$SnapToConnect = Get-EqlSnapshot -VolumeName $DataConn.VolumeName | Where-Object {$_.SnapshotDescription -eq "PresDiaria"} 
#Si el snapshot esta online en la SAN interpreto que está mapeado.
if ($SnapToConnect.IsOnline -eq $false){
    Write-Host "Cambiando estado a OnLine..." -ForegroundColor Green
    $SnapToConnect | Set-EqlSnapshot -OnlineStatus online
    Write-Host "Actualizando destinos iSCSI..." -ForegroundColor Green
    $Conn = Get-IscsiConnection
    $Conn[0] | Update-IscsiTarget
    Write-Host "Conectando a destino iSCSI..." -ForegroundColor Green
    $iSCSI_Conn = Connect-IscsiTarget -NodeAddress $DataConn.SnapshotName 
    sleep 5
}else{
    #El snapshot es ta OnLine en la SAN pero desconectado, lo conecto.
    $iSCSI_Conn = Get-IscsiSession | Where-Object {$_.TargetNodeAddress -eq $DataConn.SnapshotName} 
    if (($iSCSI_Conn.isConnected) -eq $false){
        Write-Host "Conectando a destino iSCSI..." -ForegroundColor Green
        $iSCSI_Conn = Connect-IscsiTarget -NodeAddress $DataConn.SnapshotName
    }
}
    Write-Host "Identificando disco (Esto puede tardar varios minutos)..." -ForegroundColor Green
    $Disk_ID = ""
    $Disk_ID = $iSCSI_Conn | Get-Disk

    if(-not $Disk_ID){
        Write-Host "No se pudo obtener el disco, solicite la presentación a Infraestrutura" -ForegroundColor Red
        ErrorMan $error[0]
        Break
    }
    Write-Host "Preparando disco..." -ForegroundColor Green
    if ($Disk_ID.IsReadOnly -eq $True) {$Disk_ID | Set-Disk -IsReadOnly $false}
    #CAMBIO ID DEL DISCO
    ChangeDiskID $Disk_ID
    if ($Disk_ID.IsOffline -eq $True) {$Disk_ID | Set-Disk -IsOffline $false}
    
    

    Write-Host "Obteniendo Partición..." -ForegroundColor Green
    $Particiones = $Disk_ID | Get-Partition
    
    
    #VER TEMA DISCOS DINAMICOS
    $Volume_ID = Get-Disk $Disk_ID.Number | Get-Partition | Get-Volume 
    if (-not (Test-Path $AccessPath)){
        New-Item -Path $AccessPath -Type directory
        Add-PartitionAccessPath -DiskNumber $Disk_ID.Number -PartitionNumber $Particiones[0].PartitionNumber -AccessPath $AccessPath
        Remove-PartitionAccessPath -DiskNumber $Disk_ID.Number -PartitionNumber $Particiones[0].PartitionNumber -AccessPath ((get-disk $Disk_ID.Number | Get-Partition).DriveLetter + ":")
    }

}catch{
    Write-Host "No se pudo conectar al storage, contacte a Infraestructura." -ForegroundColor Red
    ErrorMan $error[0]
    Break
}




$scriptblock = {C:\Windows\system32\subst.exe F: $AccessPath}
Invoke-Command -scriptblock $scriptblock 
Write-Host "Disco mapeado." -ForegroundColor Green
return $AccessPath

#sleep -Seconds 5
