<#
.Synopsis
   Descripción corta
.DESCRIPTION
   Descripción larga
.EXAMPLE
   Ejemplo de cómo usar este cmdlet
.EXAMPLE
   Otro ejemplo de cómo usar este cmdlet
#>
function Get-Disk
{
    [CmdletBinding()]
    [OutputType([int])]
    Param
    (
        # Descripción de ayuda de Parám1
        [Parameter(Mandatory=$true,
                   Position=0,
                   ValueFromPipeline=$TRUE)]
         #[Microsoft.Management.Infrastructure.CimInstance]$Param1,
         [System.Array]$Param_iSCSISessions,

        # Descripción de ayuda de Parám2
        [int]$Param2
    )

    Begin
    {
        #Obtengo lista de sesiones en array de strings
        $iSCSI_Session_List = iscsicli sessionlist
        #$iSCSI_Session_List = (Get-Content C:\Script\Equallogic\lista_borrar.txt)

        $TextInfo = (Get-Culture).TextInfo
        #$object = New-Object –TypeName PSObject
        $parametros = @{}
        $Discos = @()
        $Disk_out = @()

        foreach ($i in $iSCSI_Session_List)
        {
            [string]$Propiedad, [string]$Valor = $i.Split(":",2)
            $Propiedad = ($Propiedad.TrimEnd()).TrimStart()
            $Valor = ($valor.TrimEnd()).TrimStart()

             if ($Propiedad -like "Id. de sesión")
            {
                if ($parametros.Count -ne 0){
                    #creo el objeto
                    $object = New-Object PSObject -Property $parametros
                    #GUARDO EN ARRAY DE OBJETOS
                    $Discos += $object
                    Write-Verbose "Agregando objeto al Array"
                    #Reseteo parametros
                    $parametros = @{}
                }
        
                Write-Verbose "Nuevo objeto $i"
                $parametros.add((($TextInfo.ToTitleCase($Propiedad))-Replace "\s", ""), $Valor)
        
            }
            switch ($Propiedad)
            {
                "Nombre de nodo de iniciador" {$parametros.add((($TextInfo.ToTitleCase($Propiedad))-Replace "\s", ""), $Valor)}
                "Número de dispositivo" {$parametros.add("Number", $Valor)}
                "Nombre de destino" {$parametros.add((($TextInfo.ToTitleCase($Propiedad))-Replace "\s", ""), $Valor)}
                "Id. de conexión" {$parametros.add((($TextInfo.ToTitleCase($Propiedad))-Replace "\s", ""), $Valor)}
                "Nombres de ruta del volumen" {$parametros.add((($TextInfo.ToTitleCase($Propiedad))-Replace "\s", ""), $Valor)}
            }
        }
        #Guardo el ultimo objeto (muy poco elegante, mejorar!!)
        if ($parametros.Count -ne 0){
                    #creo el objeto
                    $object = New-Object PSObject -Property $parametros
                    #GUARDO EN ARRAY DE OBJETOS
                    $Discos += $object
                    Write-Verbose "Agregando objeto al Array"
                    #Reseteo parametros
                    $parametros = @{}
        }
    }
    Process
    {
        foreach ($Session in $Param_iSCSISessions){

            
                $disk_encontrado = $Discos | Where-Object {$_.NombreDeDestino -eq $Session.TargetNodeAddress}

                if ($disk_encontrado){
                    $Disk_out += $disk_encontrado
                }
            
        }

        Write-Output $Disk_out
        #$Disk_num = $Discos | Where-Object {$Discos.NombreDeDestino -eq $Param1[5].TargetNodeAddress}
    }
    End
    {
    }
}




function get-DiskInfo
{
    #Función solo para sistema operativo en español
    param( [parameter(Mandatory=$True)]
            [int]$disknumber)
    
        $cmds = "`"SELECT DISK $disknumber`"",
                "`"detail disk`""           
        
        $line = ""        
        $Salida = ""                  
        $scriptblock = [string]::Join(",",$cmds)
        $diskpart =$ExecutionContext.InvokeCommand.NewScriptBlock("$scriptblock | DISKPART")     
        $out_diskpart = Invoke-Command  -ScriptBlock $diskpart 

    foreach ($o in $out_diskpart)
    {
        if ($o -match "Volumen\s\d+"){
            $o = $o -replace '[^a-zA-Z0-9 -]', ''
            $line = $o -replace 'Volumen\s(\d+)\s+(\w|\s)\s+(.+)(NTFS)\s+(\w+)\s+(\d+\s\w{2})\s+(\w+)','$1 ; $2 ; $3 ; $4 ; $5 ; $6 ; $7'         
            $line = @($line -split(";"))
   
            $Salida = New-Object PSObject 
            $Salida | Add-Member NoteProperty NumVolume ($line[0].TrimEnd()).TrimStart()
            $Salida | Add-Member NoteProperty Ltr ($line[1].TrimEnd()).TrimStart()
            $Salida | Add-Member NoteProperty Etiqueta ($line[2].TrimEnd()).TrimStart()
            $Salida | Add-Member NoteProperty Fs ($line[3].TrimEnd()).TrimStart()
            $Salida | Add-Member NoteProperty Tipo ($line[4].TrimEnd()).TrimStart()
            $Salida | Add-Member NoteProperty Tamano ($line[5].TrimEnd()).TrimStart()
            $Salida | Add-Member NoteProperty Estado ($line[6].TrimEnd()).TrimStart()
        }
    
    }
        
        Write-Output $Salida
    
}




function Set-DiskOnline
{
    param( [parameter(Mandatory=$True)]
            [int]$disknumber)
    
        $cmds = "`"SELECT DISK $disknumber`"",
                "`"online disk`"",           
                "`"attributes disk clear readonly`"",
                "`"import`""
                          
        $scriptblock = [string]::Join(",",$cmds)
        $diskpart =$ExecutionContext.InvokeCommand.NewScriptBlock("$scriptblock | DISKPART")        
        Invoke-Command  -ScriptBlock $diskpart
    
    
}

function Set-DiskOffLine
{
    param( [parameter(Mandatory=$True)]
            [int]$disknumber,
            [string]$mountpath)
    
        $cmds = "`"SELECT VOLUME=$mountpath`"",
                "`"REMOVE ALL DISMOUNT`"",
                "`"SELECT DISK $disknumber`"",
                "`"offline disk`""                  
        $scriptblock = [string]::Join(",",$cmds)
        $diskpart =$ExecutionContext.InvokeCommand.NewScriptBlock("$scriptblock | DISKPART")        
        Invoke-Command  -ScriptBlock $diskpart
    
    
}

function ChangeDiskID
{
    param( [parameter(Mandatory=$True)][System.Object]$Disk_obj)
    #$guid = [GUID]::NewGuid()
    
    $uniqueIds = $Disk_obj
    $diskpart_out = ""
    ForEach ($uniqueId in $uniqueIds)
    {
        $guid = Get-Random -Minimum 2863311530 -Maximum 4294967295
        $guid = "{0:X0}" -f $guid
        Write-Host "Nuevo ID: $guid" -ForegroundColor Yellow
        $disknumber = $uniqueId.Number
        $cmds = "`"SELECT DISK $disknumber`"",
                "`"attributes disk clear readonly`"",
                "`"UNIQUEID DISK`"",         
                "`"UNIQUEID DISK ID=$guid`"",
                "`"UNIQUEID DISK`""        
        $scriptblock = [string]::Join(",",$cmds)
        $diskpart =$ExecutionContext.InvokeCommand.NewScriptBlock("$scriptblock | DISKPART")        
        $diskpart_out = Invoke-Command  -ScriptBlock $diskpart

        $ID_Viejo = ""
        $ID_Nuevo = ""
        foreach ($item in $diskpart_out)
        {
            if($item -match '[0-9A-F]{8}'){
                if($ID_Viejo -eq ""){
                    $ID_Viejo = $item -replace '.+: ([0-9A-F]{8}).+', '$1'
                }else{
                    $ID_Nuevo = $item -replace '.+: ([0-9A-F]{8}).+', '$1'
                }
            }
        }
        Write-Verbose ("ID Anterior: $ID_Viejo -> ID Nuevo: $ID_Nuevo")
    }
        Write-Output $diskpart_out
}

function Mount-Disk
{
    param( [parameter(Mandatory=$True)]
            [int]$disknumber,
            [int]$volnumber,
            [string] $volltr,
            [string] $mount_path)
    
        $cmds = "`"SELECT DISK $disknumber`"",
                "`"select volume $volnumber`"",
                "`"attributes volume clear hidden`"",
                "`"attributes volume clear readonly`"",
                "`"assign mount $mount_path`"",
                "`"remove letter $volltr`""
                          
        $scriptblock = [string]::Join(",",$cmds)
        $diskpart =$ExecutionContext.InvokeCommand.NewScriptBlock("$scriptblock | DISKPART")        
        Invoke-Command  -ScriptBlock $diskpart
    
    
}

