[CmdletBinding()]

#$iSCSI_Session_List = iscsicli sessionlist

$TextInfo = (Get-Culture).TextInfo
#$object = New-Object –TypeName PSObject
$parametros = @{}
$Discos = @()

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
        "Número de dispositivo" {$parametros.add((($TextInfo.ToTitleCase($Propiedad))-Replace "\s", ""), $Valor)}
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


function Set-DiskOnline
{
    param( [parameter(Mandatory=$True)][int]$disknumber)
    
        $cmds = "`"SELECT DISK $disknumber`"",
                "`"online disk`"",           
                "`"attributes disk clear readonly`"",
                "`"import`""
                          
        $scriptblock = [string]::Join(",",$cmds)
        $diskpart =$ExecutionContext.InvokeCommand.NewScriptBlock("$scriptblock | DISKPART")        
        Invoke-Command  -ScriptBlock $diskpart
    
    
}

Set-DiskOnline 27


