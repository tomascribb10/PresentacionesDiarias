$ErrorActionPreference = "Stop"
Import-Module "C:\Program Files\EqualLogic\bin\EqlPSTools.dll"

try{
[Byte[]] $key = (1..16)
$password = Get-Content C:\Script\Equallogic\sec_eql | ConvertTo-SecureString -Key $key
$username = "grpadmin"
$credential = New-Object System.Management.Automation.PSCredential($username,$password)
$SAN_list = Import-Csv C:\Script\Equallogic\SAN_list.txt
$reference_path = "C:\Script\Equallogic\referencias.cvs"
$iSCSI_inicializador = "iqn.1991-05.com.microsoft:presid01.neuralsoft.com.ar"
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
        $snapshot = Get-EqlSnapshot -GroupName $grp_name -VolumeName $_.VolumeName | Where-Object {$_.SnapshotDescription -like "PresDiaria" -and $_.IsOnLine -eq $true}
        $VolumeName = $_.VolumeName
        if ($snapshot){
            
            Write-Host "Snapshot OnLine " ($snapshot.SnapshotName) -ForegroundColor Green
        
        
        #sleep -Milliseconds 200
    }
    
    #Dejo un log en el visor de eventos.
}

}
