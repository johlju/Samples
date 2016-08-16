$script:DSCModuleName      = 'xSQLServer'
$script:DSCResourceName    = 'xSQLServerAvailabilityGroupListener'

#region HEADER

# Unit Test Template Version: 1.1.0
[String] $script:moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ( (-not (Test-Path -Path (Join-Path -Path $script:moduleRoot -ChildPath 'DSCResource.Tests'))) -or `
     (-not (Test-Path -Path (Join-Path -Path $script:moduleRoot -ChildPath 'DSCResource.Tests\TestHelper.psm1'))) )
{
    & git @('clone','https://github.com/PowerShell/DscResource.Tests.git',(Join-Path -Path $script:moduleRoot -ChildPath '\DSCResource.Tests\'))
}

Import-Module (Join-Path -Path $script:moduleRoot -ChildPath 'DSCResource.Tests\TestHelper.psm1') -Force

$TestEnvironment = Initialize-TestEnvironment `
    -DSCModuleName $script:DSCModuleName `
    -DSCResourceName $script:DSCResourceName `
    -TestType Unit 

#endregion HEADER

# Begin Testing
try
{
    #region Pester Test Initialization

    # Static parameter values
    $nodeName = 'localhost'
    $instanceName = 'DEFAULT'
    $availabilityGroup = 'AG01'
    $listnerName = 'AGListner'
    
    $defaultParameters = @{
        InstanceName = $instanceName
        NodeName = $nodeName 
        Name = $listnerName
        AvailabilityGroup = $availabilityGroup
    }

    #endregion Pester Test Initialization

    $actualIPAddress = '192.168.0.1'
    $actualSubnetMask = '255.255.255.0'
    $actualPortNumber = 5030
    $actualIsDhcp = $false

    function Get-MockSQLAlwaysOnAvailabilityGroupListener 
    {
        Mock -CommandName Get-SQLAlwaysOnAvailabilityGroupListener -MockWith {
            # TypeName: Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener
            return New-Object Object | 
                Add-Member NoteProperty PortNumber $actualPortNumber -PassThru | 
                Add-Member ScriptProperty AvailabilityGroupListenerIPAddresses {
                    return @(
                        # TypeName: Microsoft.SqlServer.Management.Smo.AvailabilityGroupListenerIPAddressCollection
                        (New-Object Object |    # TypeName: Microsoft.SqlServer.Management.Smo.AvailabilityGroupListenerIPAddress
                            Add-Member NoteProperty IsDHCP $actualIsDhcp -PassThru | 
                            Add-Member NoteProperty IPAddress $actualIPAddress -PassThru |
                            Add-Member NoteProperty SubnetMask $actualSubnetMask -PassThru
                        )
                    )
                } -PassThru -Force 
        } -Verifiable
    }
    
    Describe "$($script:DSCResourceName)\Get-TargetResource" {
        Context 'When the system is in the desired state, without DHCP' {
            $testParameters = $defaultParameters

            InModuleScope -ModuleName $script:DSCResourceName {
                Get-MockSQLAlwaysOnAvailabilityGroupListener
            }

            $result = Get-TargetResource @testParameters

            It 'Should return the desired state as present' {
                $result.Ensure | Should Be 'Present'
            }
        }

        Assert-VerifiableMocks
    }
}
finally
{
    #region FOOTER

    Restore-TestEnvironment -TestEnvironment $TestEnvironment 

    #endregion
}
