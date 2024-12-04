#$DebugPreference = “Continue”
Function Write-CustomLog {
    Param (
        [Parameter(Mandatory=$True)][string]$LogString,
        [Parameter()][bool]$WriteHost = $False
    )
    $LogFile = $PSScriptRoot.Parent.FullName + "\Log\WimProcessor.log"
    #Must use Write-Host or function returns don't work, because functions return everything from StdOut.
    If (!$WriteHost) {Write-Host ((Get-Date -format "yyyy.dd.MM HH:mm:ss:fff").ToString() + " " + $LogString)}
    Add-content $Logfile -Value ((Get-Date -format "dd.MM.yyyy HH:mm").ToString() + " " + $LogString)
}
Function CleanUp-WHDownloader {
    Param ([string]$WHDownloaderUpdatesRoot)
    #Not used

    #Only one level on depth is required
    $UpdateFolders = Get-ChildItem -Path $WHDownloaderUpdatesRoot -Directory
    #$UpdateFolders | Write-Debug
    ForEach ($UpdateFolder In $UpdateFolders) {
        #Remove outdated
        #"OLD" is magic value
        If ($UpdateFolder -match "OLD") {<#Write-Debug $UpdateFolder#>; Remove-Item -Path $UpdateFolder.FullName -Recurse -Force}
    }
}
Function Get-ImagesForProcessing {
    Param ([ValidateScript({Test-Path $_})][string][Parameter(Mandatory=$True)]$OriginalWIMFolder)
    Write-CustomLog "Start function Get-ImagesForProcessing"
    Write-CustomLog "Start logging variables before processing"
    Write-CustomLog ("Source stock WIM folder: " + $OriginalWIMFolder)
    Write-CustomLog "End logging variables before processing"

    #Get all WIM lists before processing
    Write-CustomLog ("Start get list of WIM files in folder " + $OriginalWIMFolder)
    Try {
        $SourceImages = Get-ChildItem -Path $OriginalWIMFolder -Filter *.wim
    } Catch [exception] {
        Write-CustomLog ("Failed to get list of WIM files in folder " + $OriginalWIMFolder)
        Write-CustomLog ("Exception was: " + $_.Exception.Message)
    } Finally {
        Write-CustomLog ("End get list of WIM files in folder " + $OriginalWIMFolder)
        Write-CustomLog ("Got " + $SourceImages.Count + " WIM files in folder " + $OriginalWIMFolder)
    }
        
    #$SourceImages | Write-Debug#
    Write-CustomLog ("Start initialize return object")
    $OriginalWIMData = @()
    Write-CustomLog ("End initialize return object")

    Write-CustomLog ("Start processing each WIM file")
    ForEach ($SourceImage In $SourceImages) {
        Write-CustomLog ("Start processing WIM file " + $SourceImage.FullName)
        #Write-Debug $SourceImage
        #We need to split name to get Image name and Arch
        $ImageNameTokens = $SourceImage.BaseName.Split("-")
        #$ImageNameTokens | Write-Debug
        $ImageName = $ImageNameTokens[0]
        Write-CustomLog ("Image name is " + $ImageName)
        $ImageArchitecture = $ImageNameTokens[1]
        Write-CustomLog ("Image architecture is " + $ImageArchitecture)
        
        #Check if nt6.0
        Write-CustomLog ("Start check if WIM file " + $SourceImage.FullName + " image version is NT6.0")
        Try {
            $ImageStats = Get-WindowsImage -ImagePath $SourceImage.FullName
        } Catch [exception] {
            Write-CustomLog ("Failed to get image information from " + $SourceImage.FullName + " Manual intervention required!")
            Write-CustomLog ("Exception was: " + $_.Exception.Message)
            $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Exit
        } Finally {
            If ($ImageStats.ImageName -match "Vista" -or $ImageStats.ImageName -match "Longhorn") {
                $NT60 = $True
                Write-CustomLog ("Image file " + $SourceImage.FullName + " is NT6.0")
            } Else {
                $NT60 = $False
                Write-CustomLog ("Image file " + $SourceImage.FullName + " is not NT6.0")
            }
            Write-CustomLog ("End check if WIM file is NT6.0")
        }

        
        #Count images in WIM
        #If gt 1, hardfail
        Write-CustomLog ("Start count images in WIM file " + $SourceImage.FullName)
        Try {
            $ImageCount = Get-WindowsImage -ImagePath $SourceImage.FullName
        } Catch [exception] {
            Write-CustomLog ("Failed to get WIM file info at " + $SourceImage.FullName + "Manual intervention required")
            Write-CustomLog ("Exception was: " + $_.Exception.Message)
            $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Exit
        } Finally {
            If ($ImageCount.Count -gt 1) {
                Write-CustomLog ("WIM file " + $SourceImage.FullName + " has " + $ImageCount.Count + " images in WIM file. This script requires each WIM file to have one image!")
                $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                Exit
            } Else {
                Write-CustomLog ("End count images in WIM file " + $SourceImage.FullName + " , it has " + $ImageCount.Count + " image")
            }
        }

        Write-CustomLog ("Start build image descriptor")
        $ImageObject = New-Object -TypeName PSObject
        Add-Member -InputObject $ImageObject -MemberType NoteProperty -TypeName Image -Name "Image" -Value $ImageName
        Add-Member -InputObject $ImageObject -MemberType NoteProperty -TypeName Image -Name "Path" -Value $SourceImage.FullName
        Add-Member -InputObject $ImageObject -MemberType NoteProperty -TypeName Image -Name "Architecture" -Value $ImageArchitecture
        Add-Member -InputObject $ImageObject -MemberType NoteProperty -TypeName Image -Name "NT60" -Value $NT60
        #$ImageObject.Path = $SourceImage.FullName
        #$ImageObject.Architecture = $ImageAchitecture
        #$ImageObject.NT60 = $NT60
        Write-CustomLog ("End build image descriptor")

        Write-CustomLog ("Start add image descriptor to return object")
        $OriginalWIMData += $ImageObject
        Write-CustomLog ("End add image descriptor to return object")
    }
    Write-CustomLog ("End processing each WIM file")
    Write-CustomLog ("Return data has " + $OriginalWIMData.Count + " members")
    Write-CustomLog "End function Get-ImagesForProcessing"

    Return $OriginalWIMData
}
Function Prepare-ImageForProcessing {
    Param(
        [ValidateScript({Test-Path $_})][string][Parameter(Mandatory=$True)]$ImagePath,
        [ValidateScript({If (!(Test-Path $_)) {New-Item -Path $_ -Type Directory;$True} Else {$True}})][string][Parameter(Mandatory=$True)]$TempMountDir,
        [ValidateScript({If (!(Test-Path $_)) {New-Item -Path $_ -Type Directory;$True} Else {$True}})][string][Parameter(Mandatory=$True)]$TempImageProcessing
    )
    Write-CustomLog "Start function Prepare-ImageForProcessing"
    Write-CustomLog "Start logging variables before processing"
    Write-CustomLog ("WIM file to be mounted: " + $ImagePath)
    Write-CustomLog ("WIM mount folder: " + $TempMountDir)
    Write-CustomLog ("Folder for temporary WIM processing: " + $TempImageProcessing)
    Write-CustomLog "End logging variables before processing"

    #Cleanup mounts
    #All steps are progressively more invasive so check before each try
    #If any files exist, dismount
    If (Get-ChildItem $TempMountDir) {
        Write-CustomLog ("WIM mount folder " + $TempMountDir + " is not empty, attempting dismount")
        Try {
            Dismount-WindowsImage -Path $TempMountDir -Discard | Out-Null
        } Catch [exception] {
            Write-CustomLog ("Dismount attempt at " + $TempMountDir + " failed")
            Write-CustomLog ("Exception was: " + $_.Exception.Message)
        } Finally {
            Write-Debug ("End dismount attempt at " + $TempMountDir)
        }
    }

    #If any files still exist, clear any broken mounts
    If (Get-ChildItem $TempMountDir) {
        Write-CustomLog ("WIM mount folder " + $TempMountDir + " is still not empty, attempting clear corrumpt mount point")
        Try {
            Clear-WindowsCorruptMountPoint | Out-Null
        } Catch [exception] {
            Write-CustomLog ("Corrupt mount point cleanup at " + $TempMountDir + " failed")
            Write-CustomLog ("Exception was: " + $_.Exception.Message)
        } Finally {
            Write-CustomLog "End corrupt mount point cleanup"
        }
    }

    #Last chance, any remaining files must be manually created
    If (Get-ChildItem $TempMountDir) {
        Write-CustomLog ("WIM mount folder " + $TempMountDir + " is still not empty, attempting to delete files")
        Try {
            Remove-Item -Path ($TempMountDir + "\*") -Force -Recurse | Out-Null
        } Catch [exception] {
            Write-CustomLog ("Delete files and folders mount point at " + $TempMountDir + " failed")
            Write-CustomLog ("Exception was: " + $_.Exception.Message)
        } Finally {
            If (Get-ChildItem $TempMountDir) {
                Write-CustomLog ("Cleanup at mount folder " + $TempMountDir + " has failed, manual intervention required!")
                $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                Exit
            } Else {
                Write-CustomLog "End delete files and folders at mount point"
            }
        }
    }

    #Cleanup temp WIMs
    If (Get-ChildItem $TempImageProcessing) {
        Write-CustomLog ("Start cleanup of temporary WIM files at " + $TempImageProcessing)
        Try {
            Remove-Item -Path ($TempImageProcessing + "\*") -Force -Recurse | Out-Null
        } Catch [exception] {
            Write-CustomLog ("Cleanup of temporary WIM failed at "+ $TempImageProcessing)
            Write-CustomLog ("Exception was: " + $_.Exception.Message)
        } Finally {
            If (Get-ChildItem $TempImageProcessing) {
                Write-CustomLog ("Cleanup of temporary WIM permanently failed at " + $TempImageProcessing + " Manual intervention required!")
                $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                Exit
            }
        }
    }

    #Copy file in place
    Write-CustomLog ("Start copy WIM file from " + $ImagePath + " to folder " + $TempImageProcessing)
    Try {
        $MountImagePath = Copy-Item -Path $ImagePath -Destination $TempImageProcessing -Force -PassThru 
    } Catch [exception ] {
        Write-CustomLog ("Copy WIM file from " + $ImagePath + " to folder " + $TempImageProcessing + " failed, manual intervention required!")
        Write-CustomLog ("Exception was: " + $_.Exception.Message)
        $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Exit
    } Finally {
        Write-CustomLog ("End copy WIM file " + $ImagePath + " to location " + $MountImagePath.FullName)
    }

    #Mount image
    Write-CustomLog ("Start mount WIM file " + $MountImagePath.FullName + " to folder " + $TempMountDir)
    Try {
        Mount-WindowsImage -Path $TempMountDir -ImagePath $MountImagePath.FullName -Index 1 | Out-Null
    } Catch [exception] {
        Write-CustomLog ("Failed to mount WIM file " + $MountImagePath.FullName + " at folder " + $TempMountDir)
        Write-CustomLog ("Exception was: " + $_.Exception.Message)
        $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Exit
    } Finally {
        Write-CustomLog ("End mount WIM file " + $MountImagePath.FullName + " at folder " + $TempMountDir)
    }
    Write-CustomLog "End function Prepare-ImageForProcessing"
}
Function Prepare-UpdatesForIntegration {
    Param (
        [string][Parameter(Mandatory=$True)]$Image,
        [string][Parameter(Mandatory=$True)]$Architecture,
        [ValidateScript({If (!(Test-Path $_)) {New-Item -Path $_ -Type Directory;$True} Else {$True}})][string][Parameter(Mandatory=$True)]$WHDownloaderRootFolder,
        [ValidateScript({If (!(Test-Path $_)) {New-Item -Path $_ -Type Directory;$True} Else {$True}})][string][Parameter(Mandatory=$True)]$UpdatesFolder,
        [ValidateScript({Test-Path $_})][string][Parameter(Mandatory=$True)]$ConfigurationUpdateNameCleanupFile,
        [ValidateScript({Test-Path $_})][string][Parameter(Mandatory=$True)]$ConfigurationWHDownloaderUpdateGroupsFile
    )

    #This function does not work! Do not use!
    Return

    #Temp variables for function
    $FinalUpdatesFolder = $UpdatesFolder + "\" + $Image + "\" + $Architecture
    Write-Debug $FinalUpdatesFolder
    If (!(Test-Path $FinalUpdatesFolder)) {Write-Debug "FinalUpdateFolderMissing"; New-Item -Path $FinalUpdatesFolder -ItemType Directory -Force}

    #Gather
    $FilteredUpdateFolderList = @()
    $UnfilteredUpdateFolderList = Get-ChildItem -Path ($WHDownloaderRootFolder + "\" + $Image + "-" + $Architecture) -Directory -Recurse
    $CleanupList = Import-Csv -Delimiter ";" -Path $ConfigurationWHDownloaderUpdateGroupsFile
    ForEach ($UpdateFolder in $UnfilteredUpdateFolderList) {
        ForEach ($CleanupItem In $CleanupList) {
            #Write-Debug ("UpdateFolder " + $UpdateFolder.Fullname)
            #Write-Debug ("CleanupItem " + $CleanupItem.Group)
            If (!(($UpdateFolder.FullName -match $CleanupItem.Group) -and ($CleanupItem.Action -eq "Remove"))) {$FilteredUpdateFolderList += $UpdateFolder.FullName}
        }
    }
    $FilteredUpdateFolderList = $FilteredUpdateFolderList | Select-Object -Unique
    Write-Debug FilteredUpdateFolderList
    #$FilteredUpdateFolderList | Write-Debug

    #Compare
    $TotalUpdateList = Get-ChildItem $FilteredUpdateFolderList -File | Select-Object -Unique
    #To satisfy CompareObject
    If (!$TotalUpdateList) { $TargetUpdateList = "Clean" }
    Write-Debug TotalUpdateList
    #$TotalUpdateList | Write-Debug
    $TargetUpdateList = Get-ChildItem $FinalUpdatesFolder -File -Name
    #To satisfy CompareObject
    If (!$TargetUpdateList) { $TargetUpdateList = "Empty" }
    Write-Debug TargetUpdateList
    #$TargetUpdateList | Write-Debug

    $SubsitutionTable = Import-CSV -Path $ConfigurationUpdateNameCleanupFile -Delimiter ";"
    Write-Debug SubsitutionTable
    <#ForEach ($TotalUpdate In $TotalUpdateList) {
        Write-Debug $TotalUpdate
        ForEach ($Substitution in $SubsitutionTable) {
            If (($Substitution.Image -eq $Image) -and ($Substitution.Architecture -eq $Architecture) -and ($TotalUpdate.Name -match $Substitution.OldName)) {
                $TotalUpdate.Name = $TotalUpdate.Replace($Substitution.OldName,$Substitution.NewName)
                Write-Debug $TotalUpdate.Name
            }
        }
    }#>

    <#Compare-Object -ReferenceObject $TotalUpdateList -DifferenceObject $TargetUpdateList
    If (Compare-Object -ReferenceObject $TotalUpdateList -DifferenceObject $TargetUpdateList) {
        Write-Debug "CompareFailCopy"#>
        If (Get-ChildItem $FinalUpdatesFolder) {Write-Debug "RemoveTgt"; Remove-Item -Path ($FinalUpdatesFolder + "\*") -Force -Recurse}
        Write-Debug "BeginCopy"
        Get-ChildItem $FilteredUpdateFolderList -File | Copy-Item -Destination $FinalUpdatesFolder -Force
        #$CopyCommand | ForEach-Object {Write-Host $_.FullName}
        Write-Debug "EndCopy"
        #Copy-Item -Destination $FinalUpdatesFolder -Force
        $CopiedUpdates = Get-ChildItem $FinalUpdatesFolder -File -Name
        ForEach ($CopiedUpdate In $CopiedUpdates) {
            Write-Debug $CopiedUpdate
            ForEach ($Substitution in $SubsitutionTable) {
                Write-Debug $Substitution
                If (($Substitution.Image -eq $Image) -and ($Substitution.Architecture -eq $Architecture) -and ($CopiedUpdate.Name -match $Substitution.OldName)) {
                    Write-Debug $CopiedUpdate
                    Write-Debug $Substitution
                    Rename-Item -Path $CopiedUpdate.FullName -NewName $CopiedUpdate.Name.Replace($Substitution.OldName,$Substitution.NewName)
                }
            }
        }
    #}#>
}
Function Process-Image {
    Param(
        [string][Parameter(Mandatory=$True)]$Image,
        [string][Parameter(Mandatory=$True)]$Architecture,
        [ValidateScript({If (!(Test-Path $_)) {New-Item -Path $_ -Type Directory;$True} Else {$True}})][string][Parameter(Mandatory=$True)]$TempMountDir,
        [ValidateScript({Test-Path $_})][string][Parameter(Mandatory=$True)]$ConfigurationImageFeatureActionsFile,
        [bool][Parameter(Mandatory=$True)]$NT60,
        [ValidateScript({If (!(Test-Path $_)) {New-Item -Path $_ -Type Directory;$True} Else {$True}})][string][Parameter(Mandatory=$True)]$FeatureSXSFolder,
        [ValidateScript({If (!(Test-Path $_)) {New-Item -Path $_ -Type Directory;$True} Else {$True}})][string][Parameter(Mandatory=$True)]$UpdatesFolder
    )
    Write-CustomLog "Start function Process-Image"
    Write-CustomLog "Start logging variables before processing"
    Write-CustomLog ("Image name: " + $Image)
    Write-CustomLog ("Image architecture: " + $Architecture)
    Write-CustomLog ("Image mount folder: " + $TempMountDir)
    Write-CustomLog ("Image feature configuration file: " + $ConfigurationImageFeatureActionsFile)
    Write-CustomLog ("Is image NT6.0: " + $NT60)
    Write-CustomLog ("Features on demand folder: " + $FeatureSXSFolder)
    Write-CustomLog ("Updates folder: " + $UpdatesFolder)
    Write-CustomLog "End logging variables before processing"

    #For reuse
    Write-CustomLog "Start build per-image variables"
    $ImageArchitectureUpdatesFolder = ($UpdatesFolder + "\" + $Image + "\" + $Architecture)
    $ImageArchitectureSXSFolder = ($FeatureSXSFolder + "\" + $Image + "\" + $Architecture)
    Write-CustomLog ("Per-image final updates folder:" + $ImageArchitectureUpdatesFolder)
    Write-CustomLog ("Per-image final features on demand folder:" + $ImageArchitectureSXSFolder)
    Write-CustomLog "End build per-image variables"
    #First run is always integration, followed by cleanup
    #Enabling features makes features move to pending status that blocks cleanup, so it's better to cleanup first
    <#

    #Check if nt6.0
    $ImageStats = Get-WindowsImage -ImagePath $ImagePath
    $ImageStats
    If ($ImageStats.ImageName -match "Vista" -or $ImageStats.ImageName -match "Longhorn") { $IsNT60 = $True }

    #>
    #Import Commands
    Write-CustomLog ("Start import image feature configurations from " + $ConfigurationImageFeatureActionsFile)
    Try {
        $ImageFeatureActions = Import-Csv -Delimiter ";" -Path $ConfigurationImageFeatureActionsFile
    } Catch [exception] {
        Write-CustomLog ("Failed import image feature configurations from " + $ConfigurationImageFeatureActionsFile)
        Write-CustomLog ("Exception was: " + $_.Exception.Message)
    } Finally {
        Write-CustomLog ("End import image feature configurations from " + $ConfigurationImageFeatureActionsFile)
    }

    Write-CustomLog ("Start build feature enable actions for image " + $Image + " with architecture " + $Architecture)
    [string[]]$ActionableFeatures = @()
    ForEach ($ImageFeature In $ImageFeatureActions) {
        If (($Image -eq $ImageFeature.Image) -and ($Architecture -eq $ImageFeature.Architecture) -and ($ImageFeature.Action -eq "Enable")) {
            $ActionableFeatures += [string]$ImageFeature.Feature
            If ($ImageFeature.SXS -eq "True") {
                Write-CustomLog ("Feature requires Features on Demand, enabling: " + $ImageFeature.Feature)
                $ImageActionSXS = $True
            }
        }
    }

    #If no actions, skip
    If ($ActionableFeatures) {
        Write-CustomLog ("Start enabling of features:" + $($ActionableFeatures -join ","))
        If ($ImageActionSXS) {
            Write-CustomLog "Executing with Features on Demand"
            $ExecutionCommand = "Enable-WindowsOptionalFeature -FeatureName $ActionableFeatures -Path $TempMountDir -Source $ImageArchitectureSXSFolder -All -LimitAccess"
        } Else {
            Write-CustomLog "Executing without Features on Demand"
            $ExecutionCommand = "Enable-WindowsOptionalFeature -FeatureName $ActionableFeatures -Path $TempMountDir -All -LimitAccess"
        }
        Try {
            Invoke-Expression -Command $ExecutionCommand
        } Catch [exception] {
            Write-CustomLog ("Failed enabling of features")
            Write-CustomLog ("Exception was: " + $_.Exception.Message)
        } Finally {
            Write-CustomLog ("End action enableing of features")
        }
    } Else {
        Write-CustomLog ("There are no features to be enabled")
    }
    Remove-Variable -Name ActionableFeatures

    #Build feature list
    Write-CustomLog ("Start build feature removal actions for image " + $Image + " with architecture " + $Architecture)
    [string[]]$ActionableFeatures = @()
    ForEach ($ImageFeature In $ImageFeatureActions) {
        If (($Image -eq $ImageFeature.Image) -and ($Architecture -eq $ImageFeature.Architecture) -and ($ImageFeature.Action -eq "Disable")) {
            $ActionableFeatures += [string]$ImageFeature.Feature
        }
    }
    #If no actions, skip
    If ($ActionableFeatures) {
        Write-CustomLog ("Start removal of features:" + $($ActionableFeatures -join ","))
        Try {
            Disable-WindowsOptionalFeature -FeatureName $ActionableFeatures -Path $TempMountDir | Out-Null
        } Catch [exception] {
            Write-CustomLog ("Failed removal of features")
            Write-CustomLog ("Exception was: " + $_.Exception.Message)
        } Finally {
            Write-CustomLog ("End action removal of features")
        }
    } Else {
        Write-CustomLog ("There are no features to be removed")
    }
        #Dism /Image:$TempMountDir /Cleanup-Image /SpSuperseded /HideSp
        #Dism /Image:$TempMountDir /Cleanup-Image /StartComponentCleanup /ResetBase
    #Cleanup, variable reuse
    Write-CustomLog "End removal of features"
    
    #Enable features
    #Build feature list. If SXS flag is set, include it as source


        #Enable-WindowsOptionalFeature -FeatureName $ActionableFeatures -Path $TempMountDir (&{If($ImageActionSXS){"-Source $ImageArchitectureSXSFolder"}})
        #Enable-WindowsOptionalFeature -FeatureName $ActionableFeatures -Path $TempMountDir -Source $ImageArchitectureSXSFolder
        #Apply updates again with cleanup
        #Add-WindowsPackage -PackagePath $ImageArchitectureUpdatesFolder -Path $TempMountDir
        #Dism /Image:$TempMountDir /Cleanup-Image /SpSuperseded /HideSp
        #Dism /Image:$TempMountDir /Cleanup-Image /StartComponentCleanup /ResetBase
    Write-CustomLog "End enabling of features"
    
    Write-CustomLog ("Start update integration from folder " + $ImageArchitectureUpdatesFolder)
    If (Get-ChildItem -Path $ImageArchitectureUpdatesFolder -File) {
        Write-CustomLog ("There are actionable updates")
        $NumberOfRuns = 2
        For ($i = 1; $i -le $NumberOfRuns; $i++) { 
        If (!$NT60) {
            Write-CustomLog ("NT60 is " + $NT60 + " Proceeding with DISM CmdLets")
            Write-CustomLog ("Start update integration run " + $i + " of " + $NumberOfRuns + " from " + $ImageArchitectureUpdatesFolder + " for image " + $Image + " with architecture " + $Architecture)
            Add-WindowsPackage -PackagePath $ImageArchitectureUpdatesFolder -Path $TempMountDir | Out-Null
            Write-CustomLog ("End update integration run " + $i)
            #Dism /Image:$TempMountDir /SpSuperseded /HideSp
            #Dism /Image:$TempMountDir /Cleanup-Image /StartComponentCleanup /ResetBase
        } Else {
            Write-CustomLog ("NT60 is " + $NT60 + " Proceeding with DISM EXE")
            #NT60 required only one round because PkgMgr installs CAB without checking for supersedence. Therefor, all packages are always instlled.
            #Cant use this. While it works and is much faster, it will quit DISM on error!
            #$DISMExec = "/image:`"$TempMountDir`" /add-package"
            Write-CustomLog ("Start update integration run " + $i + " of " + $NumberOfRuns + " from " + $ImageArchitectureUpdatesFolder + " for image " + $Image + " with architecture " + $Architecture)
            Write-CustomLog ("Start enumeration and update integration for NT6.0")
            If ($Architecture -eq "x86") {
                Write-CustomLog ("Architecture is 32bit")
                $PkgMgrPath = $TempMountDir + "\Windows\winsxs\x86_microsoft-windows-servicingstack_31bf3856ad364e35_6.0.6002.18005_none_0b4ada54c46c45b0\PkgMgr.exe"
                If (Test-Path $PkgMgrPath) {Write-CustomLog ("Using PkgMgr at location " + $PkgMgrPath) } Else {Write-CustomLog "PkgMgr not found!";Exit}
            } Else {
                Write-CustomLog ("Architecture is 64bit")
                $PkgMgrPath = $TempMountDir + "\Windows\winsxs\amd64_microsoft-windows-servicingstack_31bf3856ad364e35_6.0.6002.18005_none_676975d87cc9b6e6\PkgMgr.exe"
                If (Test-Path $PkgMgrPath) {Write-CustomLog ("Using PkgMgr at location " + $PkgMgrPath) } Else {Write-CustomLog "PkgMgr not found!";Exit}
            }
            
            $FileList = Get-ChildItem -Path $ImageArchitectureUpdatesFolder -Filter *.cab -File | ForEach-Object {
                Write-CustomLog ("Start integrate update " + $_.FullName + " into image " + $Image + " with architecture " + $Architecture + " mounted at " + $TempMountDir)
                #Dism quits on error, skipping most hotfixes
                #$DISMExec = $DISMExec + " /packagepath:`"$($_.FullName)`""
                #Does not seem to work via CmdLets, reports error
                #Add-WindowsPackage -PackagePath $_.FullName -Path $TempMountDir
                #Slow but stable. Spinnig up Dism takes quite some time.
                #XXX ToDo. Spin up pkgmgr in image directly, as done by DISM. Errorprone, but probably fastest.
                Remove-Item -Path "$env:TEMP\PkgMgr" -Recurse -Force *> $null
                Try {
                    New-Item -Path "$env:TEMP\PkgMgr" -ItemType Directory -Force
                    $Process = New-Object System.Diagnostics.ProcessStartInfo
                    $Process.FileName = $PkgMgrPath
                    $Process.Arguments = "/ip /m:`"$($_.FullName)`" /o:`"$TempMountDir`";`"$TempMountDir\Windows`" /s:`"$($env:TEMP)\PkgMgr`" /quiet /norestart"
                    "/image:`"$TempMountDir`" /add-package /packagepath:`"$($_.FullName)`""
                    $Process.UseShellExecute = $false
                    $Process.CreateNoWindow = $True
                    $Process.RedirectStandardOutput = $True
                    $Process.RedirectStandardError = $True
                    
                    $ProcessExecution = New-Object System.Diagnostics.Process
                    $ProcessExecution.StartInfo = $Process
                    $ProcessExecution.Start()

                    $ProcessExecution.WaitForExit()
                    Remove-Item -Path "$env:TEMP\PkgMgr" -Recurse -Force
                    If ($ProcessExecution.ExitCode -ne 0) {Throw}
                    
                    #Start-Process -FilePath "dism.exe" -ArgumentList "/image:`"$TempMountDir`" /add-package /packagepath:`"$($_.FullName)`"" -Wait -PassTru -NoNewWindow
                } Catch [exception] {
                    Write-CustomLog ("Failed integrate update into image " + $Image + " with architecture " + $Architecture + " mounted at " + $TempMountDir + " with exit code " + $ProcessExecution.ExitCode)
                    Write-CustomLog ("Command StdOut was " + $ProcessExecution.StandardOutput.ReadToEnd())
                    Write-CustomLog ("Command StdErr was " + $ProcessExecution.StandardError.ReadToEnd())
                }
                

                #DISM, does not work with x86 images from x64 system.
                <#Try {
                    $Process = New-Object System.Diagnostics.ProcessStartInfo
                    $Process.FileName = "dism.exe"
                    $Process.Arguments = "/image:`"$TempMountDir`" /add-package /packagepath:`"$($_.FullName)`""
                    $Process.UseShellExecute = $false
                    $Process.CreateNoWindow = $True
                    $Process.RedirectStandardOutput = $True
                    $Process.RedirectStandardError = $True
                    
                    $ProcessExecution = New-Object System.Diagnostics.Process
                    $ProcessExecution.StartInfo = $Process
                    $ProcessExecution.Start()

                    $ProcessExecution.WaitForExit()
                    If ($ProcessExecution.ExitCode -ne 0) {Throw}
                    
                    #Start-Process -FilePath "dism.exe" -ArgumentList "/image:`"$TempMountDir`" /add-package /packagepath:`"$($_.FullName)`"" -Wait -PassTru -NoNewWindow
                } Catch [exception] {
                    Write-CustomLog ("Failed integrate update into image " + $Image + " with architecture " + $Architecture + " mounted at " + $TempMountDir)
                    Write-CustomLog ("Command StdOut was " + $ProcessExecution.StandardOutput.ReadToEnd())
                    Write-CustomLog ("Command StdErr was " + $ProcessExecution.StandardError.ReadToEnd())
                }#>
                #Also works but pointless, as host OS's pkgmgr fires up DISM that fires image embedded pkgmgr. Better to skip and use DISM directly.
                #New-Item -Path "$env:TEMP\PkgMgr" -ItemType Directory -Force
                #Start-Process -FilePath "pkgmgr.exe" -ArgumentList "/ip /m:`"$($_.FullName)`" /o:`"$TempMountDir;$TempMountDir\Windows`" /s:`"$($env:TEMP)\PkgMgr`" /quiet /norestart" -Wait
                #Remove-Item -Path "$env:TEMP\PkgMgr" -Recurse -Force
            }
            }
            #Dism quits on error
            #Write-Output $DISMExec.ToString()
            #Start-Process -FilePath "dism.exe" -ArgumentList $DISMExec -Wait -NoNewWindow
        }
    } Else {
        Write-CustomLog ("There are no actionable updates at " + $ImageArchitectureUpdatesFolder)
    }
    Write-CustomLog "End update integration"

    #Hardcoded for now, Appx cleanup
    Write-CustomLog "Start remove Modern Application"
    If ($Image -match "Windows81" -or $Image -match "Windows10" -or $Image -match "Windows2012") {
        Write-CustomLog "Start remove action Modern Applications"
        Try {
            Get-AppxProvisionedPackage -Path $TempMountDir | Remove-AppxProvisionedPackage -Path $TempMountDir | Out-Null
        } Catch [exception] {
            Write-CustomLog ("Failed removal of Modern Applications")
            Write-CustomLog ("Exception was: " + $_.Exception.Message)
        } Finally {
            Write-CustomLog "End remove Modern Applications"
        }
    } Else {
        Write-CustomLog "This image does not support Modern Applications"
    }
}
Function Integrate-Drivers {
    [string][Parameter(Mandatory=$True)]$Image,
    [string][Parameter(Mandatory=$True)]$Architecture,
    [ValidateScript({If (!(Test-Path $_)) {New-Item -Path $_ -Type Directory;$True} Else {$True}})][string][Parameter(Mandatory=$True)]$TempMountDir,
    [ValidateScript({If (!(Test-Path $_)) {New-Item -Path $_ -Type Directory;$True} Else {$True}})][string][Parameter(Mandatory=$True)]$DriversFolder

    $ImageArchitectureDriversFolder = ($DriversFolder + "\" + $Image + "\" + $Architecture)

    Add-WindowsDriver -Driver $ImageArchitectureDriversFolder -Recurse -Path $TempMountDir
}
Function Set-Internationalization {
    Param([ValidateScript({Test-Path $_})][string][Parameter(Mandatory=$True)]$TempMountDir)
    #There seems to be no cmdlet and all functionality is common
    dism /image:"$TempMountDir" /Set-UILang:et-ee
    dism /image:"$TempMountDir" /Set-UILangFallback:en-us
    dism /image:"$TempMountDir" /Set-SysLocale:et-ee
    dism /image:"$TempMountDir" /Set-UserLocale:et-ee
    dism /image:"$TempMountDir" /Set-InputLocale:et-ee
    dism /image:"$TempMountDir" /Set-AllIntl:et-ee
    dism /image:"$TempMountDir" /Set-TimeZone:"FLE Standard Time"

    #We should use PEIMG for NT60, but it is missing on newer OS. Currently it fails for NT60
}
Function Finish-Image {
    Param(
        [ValidateScript({Test-Path $_})][string][Parameter(Mandatory=$True)]$TempMountDir,
        [ValidateScript({Test-Path $_})][string][Parameter(Mandatory=$True)]$TempImageProcessing
    )

    #Dismount
    Dismount-WindowsImage -Path $TempMountDir -Save

    #Export for space reclamation
    #Get Existing filename
    $OriginalFile = Get-ChildItem -Path $TempImageProcessing -File

    #Export
    Export-WindowsImage -SourceImagePath $OriginalFile.FullName -SourceIndex 1 -CheckIntegrity -CompressionType max -DestinationImagePath ($OriginalFile.FullName + "export")

    #Move file back
    Move-Item -Path ($OriginalFile.FullName + "export") -Destination $OriginalFile.FullName -Force
}
Function Build-ISO {
    Param(
        [string]$Image,
        [string]$Architecture,
        [string]$ISOSourceFolder,
        [string]$CompletedFolder,
        [string]$TempImageProcessing,
        [bool][Parameter(Mandatory=$True)]$NT60
    )
    #Helper
    If ($NT60) {
        $ArchitectureIsoSourceFolder = $ISOSourceFolder + "\NT60" + $Architecture
    } Else {
        $ArchitectureIsoSourceFolder = $ISOSourceFolder + "\" + $Architecture
    }
    $SourceWIM = Get-ChildItem -Path $TempImageProcessing -File
    $FinalISOPath = $CompletedFolder + "\" + $SourceWIM[0].Name + ".ISO"
    #Currently presume ADK 10
    $OSCDImg = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    #Dualboot, BIOS and UEFI
    $OSCDImgparams = "-m -o -u2 -udfver102 -bootdata:2p0,e,b$ArchitectureIsoSourceFolder\boot\etfsboot.com#pEF,e,b$ArchitectureIsoSourceFolder\efi\microsoft\boot\efisys.bin"

    #Move WIM in place
    Move-Item -Path $SourceWIM.FullName -Destination ($ArchitectureIsoSourceFolder + "\sources\install.wim") -force

    #Build ISO
    Start-Process -FilePath $OSCDImg -ArgumentList ($OSCDImgparams + " " + $ArchitectureIsoSourceFolder + " " + $FinalISOPath) -Wait

    #Move finalized ISO in place
    Move-Item -Path ($ArchitectureIsoSourceFolder + "\sources\install.wim") -Destination ($CompletedFolder + "\" + $SourceWIM[0].Name) -Force
}

#Start Here!
Function Process-WIM {
Write-CustomLog "Start procesing WIMs"
Write-CustomLog "Start logging script variables"

#Change these
$WHDownloaderUpdatesRootFolder ="D:\WHDownloader\Updates"
Write-CustomLog ("WHDownloader folder: " + $WHDownloaderUpdatesRootFolder)


#Do not change
#Variables
#Root is presumed to be .. of script
Write-CustomLog ("WIM Processing root: " + $PSScriptRoot)

[string]$RootFolder = (Get-Item $PSScriptRoot).Parent.FullName
Write-CustomLog ("WIM Processing root folder: " + $RootFolder)
#Stores configuration CSV Files
$ConfigurationFolder = $RootFolder + "\Configuration"
Write-CustomLog ("Configuration file folder: " + $ConfigurationFolder)
#Sets required configuration steps for image features
$ConfigurationImageFeatureActionsFile = $ConfigurationFolder + "\ImageFeatureActions.csv"
Write-CustomLog ("Image configuration actions file: " + $ConfigurationImageFeatureActionsFile)
#Cleans up update names (example IE11) to keep integration order consistent
$ConfigurationUpdateNameCleanupFile = $ConfigurationFolder + "\UpdateNameCleanup.csv"
Write-CustomLog ("Update name cleanup file: " + $ConfigurationUpdateNameCleanupFile)
#Removes updates that can't/shouldn't be integrated
$ConfigurationWHDownloaderUpdateGroupsFile = $ConfigurationFolder + "\WHDownloaderUpdateGroups.csv"
Write-CustomLog ("Unwanted update cleanup file: " + $ConfigurationWHDownloaderUpdateGroupsFile)
#Stores ISO and WIM files that have been completed after processing
$CompletedFolder = $RootFolder + "\Completed"
Write-CustomLog ("Completed files storage folder: " + $CompletedFolder)
#Update files to be integrated
$UpdatesFolder = $RootFolder + "\Updates"
Write-CustomLog ("Update storage folder: " + $UpdatesFolder)
#Drivers to be integrated
$DriversFolder = $RootFolder + "\Drivers"
Write-CustomLog ("Driver storage folder: " + $DriversFolder)
#Windows ISO contents for bootable DVD generation
$ISOSourceFolder = $RootFolder + "\ISOSource"
Write-CustomLog ("ISO generation source folder: " + $ISOSourceFolder)
#SXS data, mainly for Windows 8.1 .Net 3.5
$FeatureSXSFolder = $RootFolder + "\FeatureSXS"
Write-CustomLog ("Features On Demand folder: " + $FeatureSXSFolder)
#Original WIM files, readonly
$OriginalWIMFolder = $RootFolder + "\OriginalWIM"
Write-CustomLog ("Source stock WIM folder: " + $OriginalWIMFolder)
#Temp root, for temporary files while processing
$TempFolder = $RootFolder + "\Temp"
Write-CustomLog ("Processing temporary root folder: " + $TempFolder)
#Mounting target for DISM
$TempMountDir = $TempFolder + "\MountDir"
Write-CustomLog ("WIM mount folder: " + $TempMountDir)
#Temporary folder for WIM file being processed
$TempImageProcessing = $TempFolder + "\ImageProcessing"
Write-CustomLog ("Temporary WIM processing folder: " + $TempImageProcessing)
#Temporary folder for updates being prepared for integration
$TempUpdatesProcessing = $TempFolder + "\UpdatesProcessing"
Write-CustomLog ("Update preparation folder: " + $TempUpdatesProcessing)

Write-CustomLog "End logging script variables"
#Init logging data
    Write-CustomLog "Start WHDownloader cleanup"
    #CleanUp-WHDownloader $WHDownloaderUpdatesRootFolder
    Write-CustomLog "End WHDownloader cleanup"
    Write-CustomLog ("Start get list of WIM files to be processed in folder " + $OriginalWIMFolder)
    $ImageProcessingList = Get-ImagesForProcessing $OriginalWIMFolder 
    Write-CustomLog ("End get list of WIM files to be processed")
    Write-CustomLog ("Start processing each image in image processing list")
    ForEach ($Image in $ImageProcessingList) {
        Write-CustomLog ("Start processing image " + $Image.Path + " with name " + $Image.Image + " with architecture " + $Image.Architecture + " being NT6.0 is " + $Image.NT60)
        Write-CustomLog ("Start prepare image " + $Image.Path + " for processing by moving into " + $TempImageProcessing + " and mounting into " + $TempMountDir)
        Prepare-ImageForProcessing $Image.Path $TempMountDir $TempImageProcessing
        Write-CustomLog ("End prepare image " + $Image.Path + " for processing")
        #Prepare-UpdatesForIntegration $Image.Image $Image.Architecture $WHDownloaderUpdatesRootFolder $UpdatesFolder $ConfigurationUpdateNameCleanupFile $ConfigurationWHDownloaderUpdateGroupsFile
        Process-Image $Image.Image $Image.Architecture $TempMountDir $ConfigurationImageFeatureActionsFile $Image.NT60 $FeatureSXSFolder $UpdatesFolder
        #Integrate-Drivers $Image.Image $Image.Architecture $TempMountDir $DriversFolder
        Set-Internationalization $TempMountDir
        Finish-Image $TempMountDir $TempImageProcessing
        Build-ISO $Image.Image $Image.Architecture $ISOSourceFolder $CompletedFolder $TempImageProcessing $Image.NT60
    }#>
}