<#
    .SYNOPSIS
        Automatically create a pull request in several repositories

    .PARAMETER RepositoryPath
        An absolute path to the json file containing the repository information.

    .NOTES
        Must
        - Have pull-request installed; https://github.com/jd/git-pull-request
        - A configuration file ~/.netrc with the content:
          ```
          machine github.com login <github-username> password <personal access token>
          ```
        - Should be run in PS Core on Linux, for example in a Ubuntu WSL.

        There was a problem running this on Windows. The tool git-pull-request
        failed on Windows reading a temp file itself created.
        Error: "[WinError 32] The process cannot access the file because it is
                being used by another process:
                'C:\\Users\\<username>\\AppData\\Local\\Temp\\tmphto_jrie'"
#>
function Invoke-BatchPullRequest
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ClonePath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $RepositoryPath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $SourceFilePath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WorkingBranchName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $PullRequestTitle,

        [Parameter()]
        [System.String]
        $PullRequestMessage = 'This is an automatic batch pull request.',

        [Parameter(Mandatory = $true)]
        [System.String]
        $CommitMessage
    )

    # This is tested because on my WSL I needed sudo to run some of the git commands.
    if ($PSVersionTable.Platform -eq 'Unix')
    {
        if ((id -u) -ne 0)
        {
            throw 'Not running with root privileges.'
        }
    }

    $repositoryConfig = Get-Content -Path $RepositoryPath -Raw | ConvertFrom-Json

    $sourceRepository = $repositoryConfig.Source
    $sourceRepositoryPath = Join-Path -Path $ClonePath -ChildPath $sourceRepository.Name

    $destinationRepository = $repositoryConfig.Destination

    $sourceFiles = (Get-Content -Path $SourceFilePath -Raw | ConvertFrom-Json).Path

    # Make sure we are in the root of the clone folder
    Set-Location -Path $ClonePath

    Write-Verbose -Message ('Clone and rebase repository ''{0}'' and branch ''{1}''.' -f $repository.Name, $sourceRepository.Branch)

    if ($sourceRepository.Branch)
    {
        $sourceRepositoryBranch = $sourceRepository.Branch
    }
    else
    {
        # Default to dev branch.
        $sourceRepositoryBranch = 'dev'
    }

    # Get the source repository and make sure we are in the correct branch.
    if ((Test-Path -Path $sourceRepository.Name))
    {
        # Rebase the source repository
        Set-Location -Path $sourceRepository.Name
        git checkout $sourceRepositoryBranch
        git fetch origin $sourceRepositoryBranch
        git rebase remotes/origin/$sourceRepositoryBranch
    }
    else
    {
        $githubUrl = "https://github.com/$($sourceRepository.Owner)/$($sourceRepository.Name)"
        git clone $githubUrl
        Set-Location -Path $sourceRepository.Name
        git checkout $sourceRepositoryBranch
    }

    Write-Verbose -Message 'Creating batch pull requests.'

    foreach ($repository in $destinationRepository)
    {
        Write-Verbose -Message ('Evaluating if pull request is needed for repository {0}.' -f $repository.Name)

        # Make sure we are in the root of the clone folder
        Set-Location -Path $ClonePath

        if ($repository.Branch)
        {
            $repositoryBranch = $repository.Branch
        }
        else
        {
            # Default to dev branch.
            $repositoryBranch = 'dev'
        }

        # Does the repository already exist in the clone folder?
        if ((Test-Path -Path $repository.Name))
        {
            # Rebase the repository
            Set-Location -Path $repository.Name

            git checkout $repositoryBranch
            git fetch origin $repositoryBranch
            git rebase remotes/origin/$repositoryBranch
        }
        else
        {
            # Clone the repository
            $githubUrl = "https://github.com/$($repository.Owner)/$($repository.Name)"
            git clone $githubUrl
            Set-Location -Path $repository.Name
            git checkout $repositoryBranch
        }

        # Checking a new working branch (removed later if there was nothing to commit)
        $branchExist = git branch --list $WorkingBranchName
        if ( $null -eq $branchExist)
        {
            # Create a new branch based on the $repositoryBranch
            git checkout -b $WorkingBranchName --track $repositoryBranch
        }
        else
        {
            git checkout $WorkingBranchName
            # Make sure the existing branch is tracking the source repository branch.
            git branch --set-upstream-to=$repositoryBranch
        }

        <#
            TODO: Instead (maybe) of doing a foreach-loop for add, replace and
                  remove it could build up all path that should be copied and
                  then copy them in one go. Then check if there is something
                  to commit.
        #>

        # Add files, skipping if the already exist.
        foreach ($path in $sourceFiles.Add)
        {
            if (-not (Test-Path -Path $path))
            {
                # Create the destination path
                $newFolderPath = Split-Path -Path $path -Parent
                if ($newFolderPath)
                {
                    # This will do nothing if the folder exist.
                    New-Item -Path $newFolderPath -ItemType Directory -Force
                }
                else
                {
                    <#
                        Set to current directory if the path did not
                        contain a parent folder.
                    #>
                    $newFolderPath = '.'
                }

                $sourceItem = Join-Path -Path $sourceRepositoryPath -ChildPath $path
                Copy-Item -Path $sourceItem -Destination $newFolderPath

                git add $path
            }
        }

        # Replace files, overwriting existing.
        foreach ($path in $sourceFiles.Replace)
        {
            <#
                TODO: If exist, it should check if there is something to commit
                      after overwriting the file.
            #>
            if (-not (Test-Path -Path $path))
            {
                # Create the destination path
                $newFolderPath = Split-Path -Path $path -Parent
                if ($newFolderPath)
                {
                    # This will do nothing if the folder exist.
                    New-Item -Path $newFolderPath -ItemType Directory -Force
                }
                else
                {
                    <#
                        Set to current directory if the path did not
                        contain a parent folder.
                    #>
                    $newFolderPath = '.'
                }

                $sourceItem = Join-Path -Path $sourceRepositoryPath -ChildPath $path
                Copy-Item -Path $sourceItem -Destination $newFolderPath

                git add $path
            }
        }

        # Remove files
        foreach ($path in $sourceFiles.Remove)
        {
            if ((Test-Path -Path $path))
            {
                Remove-Item -Path $path

                git add $patha

                <#
                    TODO: Should check if the file was the last in the folder and
                        then also remove the empty folder, up until the root if
                        all subfolders are empty.
                #>
            }
        }

        # Only commit if there are staged changes, if not remove the working branch.
        $gitStagedChanges = git status --short
        if ($gitStagedChanges)
        {
            git commit -m $('"{0}"' -f $CommitMessage)
            # Command line arguments, see source code (no found any docs).
            git pull-request --title $('"{0}"'-f $PullRequestTitle) --message $PullRequestMessage --no-tag-previous-revision --no-rebase
            Write-Verbose -Message ('Sent pull request for repository {0}.' -f $repository.Name)
        }
        else
        {
            git checkout dev
            git branch -D $WorkingBranchName
            Write-Warning -Message ('Nothing to commit in repository {0}. Skipping.' -f $repository.Name)
        }
    }

    # End up in the clone directory.
    Set-Location -Path $ClonePath -ErrorAction Stop
}

$newPullRequestParameters = @{
    RepositoryPath    = "$PSScriptRoot/repositories.json"
    ClonePath         = '/home/johlju/source/temp/'
    SourceFilePath    = "$PSScriptRoot/sourcefiles.json"
    WorkingBranchName = 'add-templates'
    PullRequestTitle  = 'Add pull request template and issue templates'
    CommitMessage     = 'Add pull request template and issue templates'
}

# Used for debug on Windows.
# $newPullRequestParameters = @{
#     RepositoryPath    = "$PSScriptRoot\repositories.json"
#     ClonePath         = 'C:\Source\HelpUsers\johlju'
#     SourceFilePath    = "$PSScriptRoot\sourcefiles.json"
#     WorkingBranchName = 'add-templates'
#     PullRequestTitle  = 'Add pull request template and issue templates'
#     CommitMessage     = 'Add pull request template and issue templates'
# }

Invoke-BatchPullRequest @newPullRequestParameters
