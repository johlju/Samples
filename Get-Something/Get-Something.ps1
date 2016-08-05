function Get-Something
{   
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]        
        [ValidateNotNullOrEmpty()]       
        [string]$Title
    )
    
    Write-Verbose $Title    
}

Get-Something -Title "Söder Ögon Åder Råd Rädd" -Verbose
#Get-Something -Title "Ängar" -Verbose
