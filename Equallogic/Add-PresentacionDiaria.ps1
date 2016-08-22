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
   [string]$DiscName
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

    #send-MailMessage -SmtpServer $smtp -To $to -From $from -Subject $subject -Body $Mensaje -BodyAsHtml -Priority high -Encoding Unicode
    #sleep 5
}

#Agrega set de herramientas para discos dinámicos
. "C:\Script\Equallogic\Disk-Function.ps1"


#Defino variables y temas de seguridad
try{
[Byte[]] $key = (1..16)
$password = Get-Content C:\Script\Equallogic\sec_eql | ConvertTo-SecureString -Key $key
$username = "grpadmin"
$credential = New-Object System.Management.Automation.PSCredential($username,$password)
$SAN_list = Import-Csv C:\Script\Equallogic\SAN_list.txt
$reference_path = "C:\Script\Equallogic\referencias.cvs"
$iSCSI_inicializador = (Get-WmiObject -Namespace root\wmi -Class MSiSCSIInitiator_MethodClass).iSCSINodeName
$AccessPath = "C:\Servidores2\"
$Now = get-date 
}catch{
    ErrorMan $Error[0]
    Break
}


#Verifico que exista el archivo de referencias 
if (-not (Test-Path -Path $reference_path)){
    #No existe el archivo de referencia #####VER!!!#####
    Write-Host "No existe el archivo de referencia" -ForegroundColor Red
    ErrorMan "No existe el archivo de referencia"
    Break
}


#Importo el archivo de referencias
try{
$DataConn = Import-Csv $reference_path 
}catch{
    ErrorMan $Error[0]
    Break
}



#Obtengo Snapshot a renovar
$SnapToRenew = $DataConn | Where-Object {$_.VolumeName -eq $DiscName}

#Ver si seguir y crear uno nuevo.
if (-not $SnapToRenew){
            Write-Host "No se encontró el snapshot a renovar" -ForegroundColor Red
            ErrorMan $error[0]
            Break
}

$Grp_conn = Get-EqlGroup | Where-Object { $_.GroupName -eq $SnapToRenew.GroupName}

if (-not $Grp_conn){
    try{
    Connect-EqlGroup -GroupAddress $SnapToRenew.GroupAddress -GroupName $SnapToRenew.GroupName -Credential $credential -IgnoreSavedCredentials 
    $Grp_conn = Get-EqlGroup | Where-Object { $_.GroupName -eq $SnapToRenew.GroupName}
    }catch{
        ErrorMan $Error[0]
        Break
    }
}

#No se pudo conectar al grupo.
if (-not $Grp_conn){
            Write-Host "No se pudo conectar al grupo." -ForegroundColor Red
            ErrorMan $error[0]
            Break
}

 

$snapshot = Get-EqlSnapshot -GroupName $SnapToRenew.GroupName  -VolumeName $SnapToRenew.VolumeName | Where-Object {$_.SnapshotDescription -like "PresDiaria"}
$VolumeName = $_.VolumeName

Write-Host "*********************" -ForegroundColor Green
Write-Host "Procesando " ($snapshot.SnapshotName) -ForegroundColor Green

    if ($snapshot.Count -eq 1 -or $snapshot.Count -eq 0){
            
        if ($snapshot.Count -eq 1 -and $snapshot[0].IsOnline){
            #Desconecto el Snapshot
            $temp = $DataConn  | Where-Object {$_.VolumeName -eq $SnapToRenew.VolumeName}
            Write-Host "El disco" $temp.VolumeName "está mapeado." -ForegroundColor Yellow
            $iSCSI_Session = Get-IscsiSession | Where-Object {$_.TargetNodeAddress -eq $snapshot.iSCSITargetName}  
            if ($iSCSI_Session){
                $iSCSI_Disk = $iSCSI_Session[0] | Get-Disk 
                Write-Host "Pasando a Offline el Disco en el SO " -ForegroundColor Green
                Set-DiskOffLine $iSCSI_Disk[0].Number
            }
            Write-Host "Desconecto el snapshot" -ForegroundColor Green
            Disconnect-IscsiTarget -NodeAddress $snapshot.iSCSITargetName -AsJob
               
            #Pongo offline snapshot
            Write-Host "Pongo el snapshot offline" -ForegroundColor Green
            Set-EqlSnapshot -GroupName $SnapToRenew.GroupName -VolumeName $SnapToRenew.VolumeName -SnapshotName $snapshot[0].SnapshotName -OnlineStatus offline 
                
        }
        if ($snapshot.Count -eq 1){
            Write-Host "Borro el snapshot" -ForegroundColor Green
            Remove-EqlSnapshot -GroupName $SnapToRenew.GroupName -VolumeName $SnapToRenew.VolumeName -SnapshotName $snapshot[0].SnapshotName 
                
        }
        try{
            Write-Host "Generando el snapshot" -ForegroundColor Green
            $new_snapshot = New-EqlSnapshot -GroupName $SnapToRenew.GroupName -VolumeName $SnapToRenew.VolumeName -SnapshotDescription "PresDiaria" -PassThru 
               
            if(-not (Get-EqlVolumeACL -GroupName $SnapToRenew.GroupName -VolumeName $SnapToRenew.VolumeName | Where-Object {$_.InitiatorName -eq $iSCSI_inicializador})){
                Write-Host "Asignando permisos al snapshot..."
                New-EqlVolumeAcl -GroupName $SnapToRenew.GroupName -VolumeName $SnapToRenew.GroupName -InitiatorName $iSCSI_inicializador -AclTargetType snapshot_only
                    
            }
        }catch{
            Write-Host "No se pudo generar el snapshot" -ForegroundColor Red
            ErrorMan $Error[0]
            Break
        }
    }else{
        Write-Host "Exiten multiples presentaciones favor revisar " -ForegroundColor red
        ErrorMan "Exiten multiples presentaciones favor revisar "
        Break
    }



(Get-Content $reference_path) -notmatch $SnapToRenew.VolumeName  | Out-File -FilePath $reference_path


$SnapToRenew.VolumeName +","+ $SnapToRenew.iSCSITargetName +","+ $SnapToRenew.GroupName +","+ $SnapToRenew.GroupAddress +","+ $new_snapshot.ISCSITargetName | Out-File -FilePath $reference_path -Append
sleep -Milliseconds 200



