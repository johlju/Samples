function Write-ModuleStubFile {
    param
    (
        [Parameter( Mandatory )] 
        [System.String] $ModuleName,

        [Parameter( Mandatory )] 
        [System.String] $StubPath
    )

    Import-Module $ModuleName -DisableNameChecking -Force
 
    ( ( get-command -Module $ModuleName -CommandType 'Cmdlet' ) | ForEach-Object -Begin { 
        "# Suppressing this rule because these functions are from an external module"
        "# and are only being used as stubs",
        "[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUserNameAndPassWordParams', '')]"
        "param()"
        ""
    } -Process {
        $signature = $null
        $command = $_
        $endOfDefinition = $false
        $metadata = New-Object -TypeName System.Management.Automation.CommandMetaData -ArgumentList $command
        $definition = [System.Management.Automation.ProxyCommand]::Create($metadata) 
        foreach ($line in $definition -split "`n")
        {
            $line = $line -replace '\[Microsoft.SqlServer.*.\]', '[object]'
            $line = $line -replace 'SupportsShouldProcess=\$true, ', ''

            if( $line.Contains( '})' ) )
            {
                $line = $line.Remove( $line.Length - 2 )
                $endOfDefinition = $true
            }
            
            if( $line.Trim() -ne '' ) {
                $signature += "    $line"
            } else {
                $signature += $line
            }

            if( $endOfDefinition )
            {
                $signature += "`n   )"
                break
            }
        }
        
        "function $($command.Name) {"
        "$signature"
        ""
        "   throw '{0}: StubNotImplemented' -f $`MyInvocation.MyCommand"
        "}"
        ""
    } ) | Out-String | Out-File $StubPath -Encoding utf8 -Append
}

$fileName = 'E:\Source\Write-SQLPSStubFile\SQLServerStub.psm1'

Remove-Item  $fileName -ErrorAction SilentlyContinue
Write-ModuleStubFile -ModuleName 'SQLServer' -StubPath $fileName 
