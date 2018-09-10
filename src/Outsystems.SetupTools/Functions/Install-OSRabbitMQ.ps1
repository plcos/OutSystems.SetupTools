function Install-OSRabbitMQ
{
    <#
    .SYNOPSIS
    Installs or updates the Outsystems Platform server.

    .DESCRIPTION
    This will installs or updates the platform server.
    If the platform is already installed, the function will check if version to be installed is higher than the current one and update it.

    .PARAMETER InstallDir
    Where the platform will be installed. if the platform is already installed, this parameter has no effect.
    if not specified will default to %ProgramFiles%\Outsystems

    .PARAMETER SourcePath
    If specified, the function will use the sources in that path.
    If not specified it will download the sources from the Outsystems repository (default behavior).

    .PARAMETER Version
    The version to be installed.

    .EXAMPLE
    Install-OSServer -Version "10.0.823.0"
    Install-OSServer -Version "10.0.823.0" -InstallDir D:\Outsystems
    Install-OSServer -Version "10.0.823.0" -InstallDir D:\Outsystems -SourcePath c:\temp

    .NOTES
    All error are non-terminating. The function caller should decide what to do using the -ErrorAction parameter or using the $ErrorPreference variable.

    #>

    [CmdletBinding()]
    [OutputType('Outsystems.SetupTools.InstallResult')]
    param(
        [Parameter()]
        [string[]]$VirtualHosts,

        [Parameter(ParameterSetName = 'AddAdminUser')]
        [switch]$RemoveGuestUser,

        [Parameter(ParameterSetName = 'AddAdminUser', Mandatory = $true)]
        [ValidateNotNull()]
        [System.Management.Automation.Credential()]
        [System.Management.Automation.PSCredential]$AdminUser
    )

    begin
    {
        LogMessage -Function $($MyInvocation.Mycommand) -Phase 0 -Stream 0 -Message "Starting"

        # Initialize the results object
        $installResult = [pscustomobject]@{
            PSTypeName   = 'Outsystems.SetupTools.InstallResult'
            Success      = $true
            RebootNeeded = $false
            ExitCode     = 0
            Message      = 'RabbitMQ for Outsystems successfully installed'
        }

        $osInstallDir = GetServerInstallDir
        $rabbitMQErlangInstallDir = "$osInstallDir\thirdparty\Erlang"
        $rabbitMQInstallDir = "$osInstallDir\thirdparty\RabbitMQ Server"
    }

    process
    {
         ### Check phase ###
        if (-not $(IsAdmin))
        {
            LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 3 -Message "The current user is not Administrator or not running this script in an elevated session"
            WriteNonTerminalError -Message "The current user is not Administrator or not running this script in an elevated session"

            $installResult.Success = $false
            $installResult.ExitCode = -1
            $installResult.Message = 'The current user is not Administrator or not running this script in an elevated session'

            return $installResult
        }

        if ($(-not $(GetServerVersion)) -or $(-not $osInstallDir))
        {
            LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 3 -Message "Outsystems platform is not installed"
            WriteNonTerminalError -Message "Outsystems platform is not installed"

            $installResult.Success = $false
            $installResult.ExitCode = -1
            $installResult.Message = 'Outsystems platform is not installed'

            return $installResult
        }

        # Check if Erlang is installed on the right folder and has the right version
        if (-not $(GetErlangInstallDir))
        {
            LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 0 -Message "Erlang not found. We will try to download and install"
            $installErlang = $true
        }
        else
        {
            if ($(GetErlangInstallDir) -ne $rabbitMQErlangInstallDir)
            {
                LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 3 -Message "Another Erlang version was found on the machine. Installation aborted"
                WriteNonTerminalError -Message "Another Erlang version was found on the machine. Installation aborted"

                $installResult.Success = $false
                $installResult.ExitCode = -1
                $installResult.Message = 'Another Erlang version was found on the machine. Installation aborted'

                return $installResult
            }
            LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 3 -Message "The right Erlang version was found on the machine. Skipping install"
        }

        $installRabbitMQ = $true

        # Install phase
        if ($installErlang)
        {
            try
            {
                LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 0 -Message "Installing Erlang"
                $exitCode = InstallErlang -InstallDir $rabbitMQErlangInstallDir
            }
            catch
            {
                LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Exception $_.Exception -Stream 3 -Message "Error downloading or starting the Erlang installation"
                WriteNonTerminalError -Message "Error downloading or starting the Erlang installation"

                $installResult.Success = $false
                $installResult.ExitCode = -1
                $installResult.Message = 'Error downloading or starting the Erlang installation'

                return $installResult
            }

            switch ($exitCode)
            {
                0
                {
                    LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 0 -Message "Erlang successfully installed"
                }

                {$_ -in 3010, 3011}
                {
                    LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 0 -Message "Erlang successfully installed but a reboot is needed!!!!! Exit code: $exitCode"
                    $installResult.RebootNeeded = $true
                }

                default
                {
                    LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 3 -Message "Error installing Erlang. Exit code: $exitCode"
                    WriteNonTerminalError -Message "Error installing Erlang. Exit code: $exitCode"

                    $installResult.Success = $false
                    $installResult.ExitCode = $exitCode
                    $installResult.Message = 'Error installing Erlang'

                    return $installResult
                }
            }
        }

        if ($installRabbitMQ)
        {
            try
            {
                InstallRabbitMQPreReqs -RabbitBaseDir $OSRabbitMQBaseDir
            }
            catch
            {
                LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Exception $_.Exception -Stream 3 -Message "Error configuring the pre-requisites for RabbitMQ"
                WriteNonTerminalError -Message "Error configuring the pre-requisites for RabbitMQ"

                $installResult.Success = $false
                $installResult.ExitCode = -1
                $installResult.Message = 'Error configuring the pre-requisites for RabbitMQ'

                return $installResult
            }

            try
            {
                LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 0 -Message "Installing RabbitMQ"
                $exitCode = InstallRabbitMQ -InstallDir $rabbitMQInstallDir
            }
            catch
            {
                LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Exception $_.Exception -Stream 3 -Message "Error downloading or starting the RabbitMQ installation"
                WriteNonTerminalError -Message "Error downloading or starting the RabbitMQ installation"

                $installResult.Success = $false
                $installResult.ExitCode = -1
                $installResult.Message = 'Error downloading or starting the RabbitMQ installation'

                return $installResult
            }

            switch ($exitCode)
            {
                0
                {
                    LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 0 -Message "RabbitMQ successfully installed"
                }

                {$_ -in 3010, 3011}
                {
                    LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 0 -Message "RabbitMQ successfully installed but a reboot is needed!!!!! Exit code: $exitCode"
                    $installResult.RebootNeeded = $true
                }

                default
                {
                    LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 3 -Message "Error installing RabbitMQ. Exit code: $exitCode"
                    WriteNonTerminalError -Message "Error installing RabbitMQ. Exit code: $exitCode"

                    $installResult.Success = $false
                    $installResult.ExitCode = $exitCode
                    $installResult.Message = 'Error installing RabbitMQ'

                    return $installResult
                }
            }

            # Rabbit installed. Lets wait to become available
            LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 0 -Message "Waiting for RabbitMQ to become available"
            $waitCounter = 0
            do
            {
                $wait = $false
                if (-not $(isRabbitMQAvailable))
                {
                    $wait = $true
			        Start-Sleep -Seconds 5
                    $waitCounter += 5
                    LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 0 -Message "$waitCounter secs have passed while waiting for RabbitMQ to become available ..."
                }

                if($waitCounter -ge $OSRabbitMQServiceWaitTimeout) {
                    LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 3 -Message "Timeout occurred while waiting for RabbitMQ to become available"
                    WriteNonTerminalError -Message "Timeout occurred while waiting for RabbitMQ to become available"

                    $installResult.Success = $false
                    $installResult.ExitCode = $exitCode
                    $installResult.Message = 'Timeout occurred while waiting for RabbitMQ to become available'

                    return $installResult
                }
            }
            while ($wait)

            LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 0 -Message "RabbitMQ is now available!!"

            foreach ($virtualHost in $VirtualHosts)
            {
                try {
                    LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 0 -Message "Adding virtual host $virtualHost"
                    RabbitMQAddVirtualHost -VirtualHost $virtualHost
                }
                catch {
                    LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Exception $_.Exception -Stream 3 -Message "Error adding the virtual host $virtualHost to RabbitMQ"
                    WriteNonTerminalError -Message "Error adding the virtual host $virtualHost to RabbitMQ"

                    $installResult.Success = $false
                    $installResult.ExitCode = -1
                    $installResult.Message = "Error adding the virtual host $virtualHost to RabbitMQ"

                    return $installResult
                }
            }

            if ($PsCmdlet.ParameterSetName -eq 'AddAdminUser')
            {
                try {
                    LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 0 -Message "Adding admin user $($AdminUser.UserName)"
                    RabbitMQAddAdminUser -Credential $AdminUser
                    RabbitMQAddAPermisionToAllVirtualHosts -User $($AdminUser.UserName)
                }
                catch {
                    LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Exception $_.Exception -Stream 3 -Message "Error adding admin user $($AdminUser.UserName) or setting permissions on the virtual hosts"
                    WriteNonTerminalError -Message "Error adding admin user $($AdminUser.UserName) or setting permissions on the virtual hosts"

                    $installResult.Success = $false
                    $installResult.ExitCode = -1
                    $installResult.Message = "Error adding admin user $($AdminUser.UserName) or setting permissions on the virtual hosts"

                    return $installResult
                }

                if ($RemoveGuestUser)
                {
                    try {
                        LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Stream 0 -Message "Removing guest user from RabbitMQ"
                        RabbitMQRemoveGuestUser -Credential $AdminUser
                    }
                    catch {
                        LogMessage -Function $($MyInvocation.Mycommand) -Phase 1 -Exception $_.Exception -Stream 3 -Message "Error removing guest user from RabbitMQ"
                        WriteNonTerminalError -Message "Error removing guest user from RabbitMQ"

                        $installResult.Success = $false
                        $installResult.ExitCode = -1
                        $installResult.Message = "Error removing guest user from RabbitMQ"

                        return $installResult
                    }
                }
            }
        }

        if ($installResult.RebootNeeded)
        {
            $installResult.ExitCode = 3010
            $installResult.Message = 'RabbitMQ for Outsystems successfully installed but a reboot is needed'
        }
        return $installResult
    }

    end
    {
        LogMessage -Function $($MyInvocation.Mycommand) -Phase 2 -Stream 0 -Message "Ending"
    }
}