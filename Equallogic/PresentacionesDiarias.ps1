$ErrorActionPreference = "Stop"
Import-Module "C:\Program Files\EqualLogic\bin\EqlPSTools.dll"

function ErrorMan
{
    param( [parameter(Mandatory=$True)][string]$Mensaje)
    $smtp = "192.168.3.2" 
    $to = "tomas.cribb@neuralsoft.com"
    $from = "informes@neuralsoft.com" 
    $subject = "Error en PresentacionesDiarias.ps1"

    $Evento = ""
    $Evento += $Mensaje

    Write-EventLog -LogName "Application" -Source "PresentacionesDiarias" -EventID 3011 -EntryType Error -Message $Evento  -Category 1 -RawData 10,20

    #send-MailMessage -SmtpServer $smtp -To $to -From $from -Subject $subject -Body $Mensaje -BodyAsHtml -Priority high -Encoding Unicode
    #sleep 5
}

#Agrega set de herramientas para discos dinámicos
. "C:\Script\Equallogic\Disk-Function.ps1"
$Now = get-date 

try{
[Byte[]] $key = (1..16)
$password = Get-Content C:\Script\Equallogic\sec_eql | ConvertTo-SecureString -Key $key
$username = "grpadmin"
$credential = New-Object System.Management.Automation.PSCredential($username,$password)
$SAN_list = Import-Csv C:\Script\Equallogic\SAN_list.txt
$reference_path = "C:\Script\Equallogic\referencias.cvs"
$iSCSI_inicializador = (Get-WmiObject -Namespace root\wmi -Class MSiSCSIInitiator_MethodClass).iSCSINodeName
$AccessPath = "C:\Servidores2\"
}catch{
    ErrorMan $Error[0]
    Break
}


#Desconecto los grupos
Get-EqlGroup | Disconnect-EqlGroup


$SAN_list | ForEach-Object {
    try{
    Connect-EqlGroup -GroupAddress $_.grp_address -GroupName $_.grp_name -Credential $credential -IgnoreSavedCredentials
    }catch{
        ErrorMan $Error[0]
        Break
    }
}


$Grp_conn = Get-EqlGroup 

if (-not (Test-Path -Path $reference_path)){
    #No existe el archivo de referencia #####VER!!!#####
    Write-Host "No existe el archivo de referencia" -ForegroundColor Red
    ErrorMan "No existe el archivo de referencia"
    Break
}

try{
$DataConn = Import-Csv $reference_path 
}catch{
    ErrorMan $Error[0]
    Break
}

try{
 Remove-Item $reference_path 
 "VolumeName,iSCSITargetName,GroupName,GroupAddress,SnapshotName" | Out-File -FilePath $reference_path -Append

}catch{
    ErrorMan $Error[0]
    Break
}



$Grp_conn | ForEach-Object {
    try{
        $grp_name = $_.GroupName
        #$grp_address = $SAN_list.grp_address | Where-Object {$grp_name -eq $SAN_list.grp_name}
        $grp_address = Resolve-DnsName  "$grp_name.neuralsoft.com.ar"
        $grp_address = $grp_address.IPAddress
    }catch{
        Write-Host "No se pudo resolver el nombre de la SAN" -ForegroundColor Red
        ErrorMan $Error[0]
        Break
    }

    Write-Host "Obteniendo lista de volumenes..." -ForegroundColor Green
    try{
        $Vol_list = Get-EqlVolume -GroupId $_.groupId -OnlineStatus online | Where-Object {$_.VolumeName -match "^NV0\d{1,3}-F$"} | Select-Object VolumeName, iSCSITargetName 
        #$Vol_list = Get-EqlVolume -GroupId $_.groupId -OnlineStatus online | Where-Object {$_.VolumeName -like "NV0999-F"} | Select-Object VolumeName, iSCSITargetName 
    }catch{
        Write-Host "No se pudo obtenet la lista de volúmenes" -ForegroundColor Red
        ErrorMan $Error[0]
        Break
    }
    



    #Genero el archivo de referencias.
    $Vol_list | ForEach-Object {
        $snapshot = Get-EqlSnapshot -GroupName $grp_name -VolumeName $_.VolumeName | Where-Object {$_.SnapshotDescription -like "PresDiaria"}
        $VolumeName = $_.VolumeName
        $MountPath = "$AccessPath$VolumeName"
        
        Write-Host "*********************" -ForegroundColor Green
        Write-Host "Procesando " ($snapshot.SnapshotName) -ForegroundColor Green

        if ($snapshot.Count -eq 1 -or $snapshot.Count -eq 0){
            
            if ($snapshot.Count -eq 1 -and $snapshot[0].IsOnline){
                #Desconecto el Snapshot
                $temp = $DataConn  | Where-Object {$_.VolumeName -eq $VolumeName}
                Write-Host "El disco" $temp.VolumeName "está mapeado." -ForegroundColor Yellow
                $iSCSI_Session = Get-IscsiSession | Where-Object {$_.TargetNodeAddress -eq $snapshot.iSCSITargetName}  
                if ($iSCSI_Session){
                    $iSCSI_Disk = $iSCSI_Session | Get-Disk 
                    Write-Host "Pasando a Offline el Disco en el SO " -ForegroundColor Green
                    Set-DiskOffLine $iSCSI_Disk[0].Number $MountPath
                }
                Write-Host "Desconecto el snapshot" -ForegroundColor Green
                Disconnect-IscsiTarget -NodeAddress $snapshot.iSCSITargetName -AsJob
               
                #Pongo offline snapshot
                Write-Host "Pongo el snapshot offline" -ForegroundColor Green
                Set-EqlSnapshot -GroupName $grp_name -VolumeName $VolumeName -SnapshotName $snapshot[0].SnapshotName -OnlineStatus offline 
                
            }
            if ($snapshot.Count -eq 1){
                Write-Host "Borro el snapshot" -ForegroundColor Green
                Remove-EqlSnapshot -GroupName $grp_name -VolumeName $VolumeName -SnapshotName $snapshot[0].SnapshotName 
                
            }
            try{
                Write-Host "Generando el snapshot" -ForegroundColor Green
                $new_snapshot = New-EqlSnapshot -GroupName $grp_name -VolumeName $VolumeName -SnapshotDescription "PresDiaria" -PassThru 
               
                if(-not (Get-EqlVolumeACL -GroupName $grp_name -VolumeName $VolumeName | Where-Object {$_.InitiatorName -eq $iSCSI_inicializador})){
                    Write-Host "Asignando permisos al snapshot..."
                    New-EqlVolumeAcl -GroupName $grp_name -VolumeName $VolumeName -InitiatorName $iSCSI_inicializador -AclTargetType snapshot_only
                    
                }
            }catch{
                Write-Host "No se pudo generar el snapshot" -ForegroundColor Red
                ErrorMan $Error[0]
                Break
            }
        }else{
            Write-Host "Exiten multiples presentaciones favor revisar " -ForegroundColor red
            ErrorMan "Exiten multiples presentaciones favor revisar "
            
        }
        
       
        $_.VolumeName +","+ $_.iSCSITargetName +","+ $grp_name +","+ $grp_address +","+ $new_snapshot.ISCSITargetName | Out-File -FilePath $reference_path -Append
        sleep -Milliseconds 200
    }
    Write-EventLog -LogName "Application" -Source "PresentacionesDiarias" -EventID 3001 -EntryType Information -Message "Se generaron los snapshot diarios." -Category 1 -RawData 10,20
    #Dejo un log en el visor de eventos.
}


