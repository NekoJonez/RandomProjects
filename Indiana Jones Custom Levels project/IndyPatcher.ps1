# NekoJonez presents Indiana Jones and the Infernal Machine - Automatic Patcher for custom levels.
# Based upon the work & tools by the modders over at https://github.com/Jones3D-The-Infernal-Engine/Mods/tree/main/levels/sed
# Written in PowerShell core 7.4.3. Will work with PowerShell 5.1 & 7+.
# Build 1.0 BETA 2 - 15/07/2024
# Visit my gaming blog: https://arpegi.wordpress.com

# Function to move files while skipping existing files
function MoveFilesAndRemoveSource {
    param (
        [string]$sourcePath,
        [string]$destinationPath,
        [string[]]$subfolders
    )

    # Get subfolders within the source path
    foreach ($subfolder in $subfolders) {
        $fullSourcePath = Join-Path -Path $sourcePath -ChildPath $subfolder
        $fullDestinationPath = Join-Path -Path $destinationPath -ChildPath $subfolder

        # Check if source subfolder exists
        if (Test-Path -Path $fullSourcePath -PathType Container) {
            # Ensure destination subfolder exists
            if (!(Test-Path -Path $fullDestinationPath -PathType Container)) {
                New-Item -Path $fullDestinationPath -ItemType Directory | Out-Null
            }

            # Move files from source subfolder to destination subfolder
            Get-ChildItem -Path $fullSourcePath -File | ForEach-Object {
                $destinationFile = Join-Path -Path $fullDestinationPath -ChildPath $_.Name

                # Check if file already exists in destination
                if (!(Test-Path -Path $destinationFile -PathType Leaf)) {
                    Move-Item -Path $_.FullName -Destination $destinationFile -Force
                    Write-Host "Success: $($_.FullName) moved to $destinationFile"
                }
                else {
                    Write-Host "Skipped: $($_.FullName) already exists at $destinationFile"
                }
            }

            # Remove the source subfolder after moving its contents
            Remove-Item -Path $fullSourcePath -Force -Recurse
            Write-Host "Success: Removed $fullSourcePath"
        }
    }
}

# Let's edit the reg key.
function Update-RegistryStartMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$registryPath
    )

    $keyName = "Start mode"
    $desiredValue = 2

    # Check if the registry path exists
    if (Test-Path $registryPath) {
        # Check if the Start mode DWORD value exists
        $startModeValue = Get-ItemProperty -Path $registryPath -Name $keyName -ErrorAction SilentlyContinue
        if ($startModeValue -ne $null) {
            # Check if the current value is different from desired value, then update it
            if ($startModeValue.$keyName -ne $desiredValue) {
                Set-ItemProperty -Path $registryPath -Name $keyName -Value $desiredValue
                Write-Output "Updated $keyName in $registryPath to $desiredValue"
            }
            else {
                Write-Output "$keyName in $registryPath already has the desired value $desiredValue"
            }
        }
        else {
            Write-Output "The DWORD value $keyName does not exist in $registryPath"
        }
    }
    else {
        Write-Output "Registry path $registryPath does not exist"
    }
}

# Let's show a form on screen.
Add-Type -AssemblyName System.Windows.Forms

if (!(New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    [System.Windows.Forms.MessageBox]::Show("This script needs to be run as administrator. Since the patch needs to change a reg key, and you can't do that without admin permissions.", "Admin Rights Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    exit
}

# Create the form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Indiana Jones and the Infernal Machine - Custom level patcher"
$form.Size = New-Object System.Drawing.Size(1000, 1000)
$form.StartPosition = "CenterScreen"

# Let's create column styles.
$columnStyle1_location = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 90)
$columnStyle2_location = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 10)

# Create the TableLayoutPanel, so that it's better visually and I don't have to guess their location.
$tableLayoutPanel = New-Object System.Windows.Forms.TableLayoutPanel
$tableLayoutPanel.RowCount = 6
$tableLayoutPanel.ColumnCount = 1
$tableLayoutPanel.Dock = [System.Windows.Forms.DockStyle]::Fill

# Create a label for the install location
$label_location = New-Object System.Windows.Forms.Label
$label_location.Text = "Enter your resources location:"
$label_location.AutoSize = $true
$label_location.Dock = [System.Windows.Forms.DockStyle]::Fill
$label_location.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$tableLayoutPanel.Controls.Add($label_location)

# For the locate button.
$tableLayoutPanelLocation = New-Object System.Windows.Forms.TableLayoutPanel
$tableLayoutPanelLocation.Dock = [System.Windows.Forms.DockStyle]::Fill
$tableLayoutPanelLocation.RowCount = 1
$tableLayoutPanelLocation.ColumnCount = 2
$tableLayoutPanelLocation.ColumnStyles.Add($columnStyle1_location)
$tableLayoutPanelLocation.ColumnStyles.Add($columnStyle2_location)
$tableLayoutPanel.Controls.Add($tableLayoutPanelLocation)

# Create a text box for user input
$textBox_location = New-Object System.Windows.Forms.TextBox
$textBox_location.Dock = [System.Windows.Forms.DockStyle]::Fill
$textBox_location.AutoSize = $true
$tableLayoutPanelLocation.Controls.Add($textBox_location)

# Create a button for the user to locate the resources folder
$button_location = New-Object System.Windows.Forms.Button
$button_location.Text = "Search"
$button_location.AutoSize = $true
$button_location.Cursor = [System.Windows.Forms.Cursors]::Hand
$tableLayoutPanelLocation.Controls.Add($button_location)

# Add the click event for the button
$button_location.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select the folder"
    $folderBrowser.ShowNewFolderButton = $true

    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textBox_location.Text = $folderBrowser.SelectedPath
    }
})

# Create a label for the tools location
$label_regkey = New-Object System.Windows.Forms.Label
$label_regkey.Text = "Select the version you want to patch:"
$label_regkey.AutoSize = $true
$label_regkey.Dock = [System.Windows.Forms.DockStyle]::Fill
$label_regkey.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$tableLayoutPanel.Controls.Add($label_regkey)

# TODO: implement a feature to only to the dev mode and to revert the dev mode.
# Create a ComboBox (dropdown box) so the reg key is easier to find later.
$comboBox = New-Object System.Windows.Forms.ComboBox
$comboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$comboBox.Items.AddRange(@("Install via original CD's", "Copied files from original CD's", "Steam version", "GOG version"))
$comboBox.SelectedIndex = 0  # Set default selection
$comboBox.AutoSize = $true
$comboBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$tableLayoutPanel.Controls.Add($comboBox)

# Create a button to start the patching proceess
$button = New-Object System.Windows.Forms.Button
$button.Text = "Patch"
$button.Dock = [System.Windows.Forms.DockStyle]::Fill
$button.Cursor = [System.Windows.Forms.Cursors]::Hand
$tableLayoutPanel.Controls.Add($button)

# Create a text box for logs
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$logBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$tableLayoutPanel.Controls.Add($logBox)

# Add button click event
$button.Add_Click({
        # TODO: implement a lock here for the other buttons.
        # TODO: implement when return, to unlock the inputs. So, it's time for a boolean variable. Phft, refactoring :/
        if ($textBox_location.Text) {
            $folder_path = $textBox_location.Text

            if ($folder_path -like "*\Resource") {
                # First check done.
            }
            else {
                $logBox.AppendText("Error: Invalid resource path provided. Stopping pathing procedure.`n")
                return
            }

            $location_checker = Join-Path -Path $textBox_location -ChildPath "Jones3D.exe"
            if (Test-Path -Path $location_checker) {
                # We can continue, it's most likely the installation folder. We could implement it better, but for this version I feel lazy.
            }
            else {
                $logBox.AppendText("Error: Invalid resource path provided. Stopping pathing procedure.`n")
                return
            }
        }
        else {
            $logBox.AppendText("Error: Invalid reesource path provided. Stopping pathing procedure.`n")
            return
        }

        # Let's download the working version of the tools. I'm going to hardcode v0.10.1 here for now, since if Kovic's PR (https://github.com/smlu/Urgon/pull/11) ever gets merged,
        # later logic will need to change.
        $Temp_Path = "C:\IndyPatcher_Temp"
        $Tools_Temp_Path = "C:\IndyPatcher_Temp\urgon-windows-x86-64.zip"
        if (Test-Path -Path $Temp_Path) {
            New-Item -Path $Temp_Path -Type Directory
        }

        try {
            Invoke-WebRequest -Uri https://github.com/smlu/Urgon/releases/download/v0.10.1/urgon-windows-x86-64.zip -OutFile $Tools_Temp_Path
            $logBox.AppendText("Success: Tools v0.10.1 succesfully downloaded.`n")
        }
        catch {
            $logBox.AppendText("Error: Tools couldn't be downloaded. $($_.Exception.Message). Stopping pathing procedure.`n")
            return
        }

        try {
            Expand-Archive -Path $Tools_Temp_Path -DestinationPath $textbox_location.Text
            $logBox.AppendText("Success: Tools v0.10.1 succesfully extracted from zip file and placed in resource folder.`n")
        }
        catch {
            $logBox.AppendText("Error: Tools couldn't be extracted and moved. $($_.Exception.Message). Stopping pathing procedure.`n")
            return
        }

        # Let's go to that resource folder.
        Set-Location $textBox_location.Text

        # Let's first extract those GOB files. Since, this tool doesn't really work with extracting to the desired folder, let's move the files afterwards.
        $gob_tool_test = Join-Path $textBox_location.Text -ChildPath "gobext.exe"
        $gob_extract_cd1 = Join-Path $textBox_location.Text -ChildPath "CD1.gob"
        $gob_extract_cd2 = Join-Path $textBox_location.Text -ChildPath "CD2.gob"
        $gob_extract_jones3d = Join-Path $textBox_location.Text -ChildPath "JONES3D.gob"
        if (Test-Path -Path $gob_tool_test) {
            if (Test-Path -Path $gob_extract_cd1) {
                .\gobext.exe CD1.GOB
                $logBox.AppendText("Success: CD1.GOB successfully extracted.`n")
            }
            else {
                $logBox.AppendText("Error: CD1.GOB was missing and wasn't extracted.`n")
                return
            }

            if (Test-Path -Path $gob_extract_cd2) {
                .\gobext.exe CD2.GOB
                $logBox.AppendText("Success: CD2.GOB successfully extracted.`n")
            }
            else {
                $logBox.AppendText("Error: CD2.GOB was missing and wasn't extracted.`n")
                return
            }

            if (Test-Path -Path $gob_extract_jones3d) {
                .\gobext.exe JONES3D.GOB
                $logBox.AppendText("Success: JONES3D.GOB successfully extracted.`n")
            }
            else {
                $logBox.AppendText("Error: JONES3D.GOB was missing and wasn't extracted.`n")
                return
            }

            # Now it's save that there are three new extraction folders. Let's get to work moving the folders.
        }
        else {
            $logBox.AppendText("Error: gobext.exe not found in the correct location. Stopping pathing procedure.`n")
            return
        }

        # ! Warning to later self. Kovic created a patch PR that the gobext.exe doesn't work with sub folders anymore. If a newer version releases, refactor the code underneath here.
        # Define source parent folders and destination folder
        $cd1_gob_location = Join-Path $textbox_location.text -ChildPath "CD1_GOB"
        $cd2_gob_location = Join-Path $textbox_location.text -ChildPath "CD2_GOB"
        $jones3d_gob_location = Join-Path $textbox_location.text -ChildPath "JONES3D_GOB"
        $destinationPath = $textbox_location.text

        # Define subfolders for each parent folder
        $cd1_and_2_subfolders = @("3do", "cog", "hi3do", "mat", "misc", "ndy")
        $jones3d_subfolders = @("3do", "cog", "mat", "misc", "ndy")

        # Call the function for each source parent folder with respective subfolders
        MoveFilesAndRemoveSource -sourcePath $cd1_gob_location -destinationPath $destinationPath -subfolders $cd1_and_2_subfolders
        MoveFilesAndRemoveSource -sourcePath $cd2_gob_location -destinationPath $destinationPath -subfolders $cd1_and_2_subfolders
        MoveFilesAndRemoveSource -sourcePath $jones3d_gob_location -destinationPath $destinationPath -subfolders $jones3d_subfolders

        # Now, let's remove the GOB files. Since, it's going to work :-)
        $filePathsToRemove = @($gob_extract_cd1, $gob_extract_cd2, $gob_extract_jones3d)

        # Remove files using foreach loop, after this step 2 is done.
        foreach ($filePathToRemove in $filePathsToRemove) {
            if (Test-Path -Path $filePathToRemove) {
                $fileDirectory = [System.IO.Path]::GetDirectoryName($filePathToRemove)
                $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePathToRemove)
                $fileExtension = [System.IO.Path]::GetExtension($filePathToRemove)

                $newFileName = "$fileName`_backup$fileExtension"
                $newFilePath = [System.IO.Path]::Combine($fileDirectory, $newFileName)

                Rename-Item -Path $filePathToRemove -NewName $newFilePath -Force
            }
        }

        $logBox.AppendText("Success: GOB files were renamed succesfully. You can remove the '_backup' if you want to reuse the standard ones.`n")

        # Now, let's move the CNDtool to it's rightful location.
        $cnd_tool_test = Join-Path $textBox_location.Text -ChildPath "cndtool.exe"
        $ndy_folder_location = Join-Path $textBox_location.text -ChildPath "ndy"
        if (Test-Path -Path $cnd_tool_test) {
            if (Test-Path -Path $ndy_folder_location) {
                Move-Item -Path $cnd_tool_test -Destination $ndy_folder_location
            }
            else {
                $logBox.AppendText("Error: NDY folder not found. Stopping the patching.`n")
                return
            }
        }
        else {
            $logBox.AppendText("Error: CND tool not found. Stopping the patching.`n")
            return
        }

        Set-Location $ndy_folder_location

        # The massive wall of CND variables.
        $cnd_extract_lvl01 = Join-Path $textBox_location.Text -ChildPath "ndy\00_cyn.cnd"
        $cnd_extract_lvl02 = Join-Path $textBox_location.Text -ChildPath "ndy\01_bab.cnd"
        $cnd_extract_lvl03 = Join-Path $textBox_location.Text -ChildPath "ndy\02_riv.cnd"
        $cnd_extract_lvl04 = Join-Path $textBox_location.Text -ChildPath "ndy\03_shs.cnd"
        $cnd_extract_lvl05 = Join-Path $textBox_location.Text -ChildPath "ndy\05_lag.cnd"
        $cnd_extract_lvl06 = Join-Path $textBox_location.Text -ChildPath "ndy\06_vol.cnd"
        $cnd_extract_lvl07 = Join-Path $textBox_location.Text -ChildPath "ndy\07_tem.cnd"
        $cnd_extract_lvl08 = Join-Path $textBox_location.Text -ChildPath "ndy\08_teo.cnd"
        $cnd_extract_lvl09 = Join-Path $textBox_location.Text -ChildPath "ndy\09_olv.cnd"
        $cnd_extract_lvl10 = Join-Path $textBox_location.Text -ChildPath "ndy\10_sea.cnd"
        $cnd_extract_lvl11 = Join-Path $textBox_location.Text -ChildPath "ndy\11_pyr.cnd"
        $cnd_extract_lvl12 = Join-Path $textBox_location.Text -ChildPath "ndy\12_sol.cnd"
        $cnd_extract_lvl13 = Join-Path $textBox_location.Text -ChildPath "ndy\13_nub.cnd"
        $cnd_extract_lvl14 = Join-Path $textBox_location.Text -ChildPath "ndy\14_inf.cnd"
        $cnd_extract_lvl15 = Join-Path $textBox_location.Text -ChildPath "ndy\15_aet.cnd"
        $cnd_extract_lvl16 = Join-Path $textBox_location.Text -ChildPath "ndy\16_jep.cnd"
        $cnd_extract_lvl17 = Join-Path $textBox_location.Text -ChildPath "ndy\17_pru.cnd"
        $cnd_extract_lvl18 = Join-Path $textBox_location.Text -ChildPath "ndy\jones3dstatic.cnd"

        if (Test-Path -Path $cnd_extract_lvl01) {
            $logBox.AppendText("Success: NDY file for level 01 found. Extracting...`n")
            .\cndtool.exe extract .\00_cyn.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 01 not found. Stopping the patching.`n")
            return
        }

        if (Test-Path -Path $cnd_extract_lvl02) {
            $logBox.AppendText("Success: NDY file for level 02 found. Extracting...`n")
            .\cndtool.exe extract .\01_bab.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 02 not found. Stopping the patching.`n")
            return
        }

        if (Test-Path -Path $cnd_extract_lvl03) {
            $logBox.AppendText("Success: NDY file for level 03 found. Extracting...`n")
            .\cndtool.exe extract .\02_riv.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 03 not found. Stopping the patching.`n")
            return
        }

        if (Test-Path -Path $cnd_extract_lvl04) {
            $logBox.AppendText("Success: NDY file for level 04 found. Extracting...`n")
            .\cndtool.exe extract .\03_shs.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 04 not found. Stopping the patching.`n")
            return
        }

        if (Test-Path -Path $cnd_extract_lvl05) {
            $logBox.AppendText("Success: NDY file for level 05 found. Extracting...`n")
            .\cndtool.exe extract .\05_lag.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 05 not found. Stopping the patching.`n")
            return
        }

        if (Test-Path -Path $cnd_extract_lvl06) {
            $logBox.AppendText("Success: NDY file for level 06 found. Extracting...`n")
            .\cndtool.exe extract .\06_vol.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 06 not found. Stopping the patching.`n")
            return
        }

        if (Test-Path -Path $cnd_extract_lvl07) {
            $logBox.AppendText("Success: NDY file for level 07 found. Extracting...`n")
            .\cndtool.exe extract .\07_tem.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 07 not found. Stopping the patching.`n")
            return
        }

        if (Test-Path -Path $cnd_extract_lvl08) {
            $logBox.AppendText("Success: NDY file for level 08 found. Extracting...`n")
            .\cndtool.exe extract .\08_teo.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 08 not found. Stopping the patching.`n")
            return
        }

        if (Test-Path -Path $cnd_extract_lvl09) {
            $logBox.AppendText("Success: NDY file for level 09 found. Extracting...`n")
            .\cndtool.exe extract .\09_olv.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 09 not found. Stopping the patching.`n")
            return
        }

        if (Test-Path -Path $cnd_extract_lvl10) {
            $logBox.AppendText("Success: NDY file for level 10 found. Extracting...`n")
            .\cndtool.exe extract .\10_sea.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 10 not found. Stopping the patching.`n")
            return
        }

        if (Test-Path -Path $cnd_extract_lvl11) {
            $logBox.AppendText("Success: NDY file for level 11 found. Extracting...`n")
            .\cndtool.exe extract .\11_pyr.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 11 not found. Stopping the patching.`n")
            return
        }

        if (Test-Path -Path $cnd_extract_lvl12) {
            $logBox.AppendText("Success: NDY file for level 12 found. Extracting...`n")
            .\cndtool.exe extract .\12_sol.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 12 not found. Stopping the patching.`n")
            return
        }

        if (Test-Path -Path $cnd_extract_lvl13) {
            $logBox.AppendText("Success: NDY file for level 13 found. Extracting...`n")
            .\cndtool.exe extract .\13_nub.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 13 not found. Stopping the patching.`n")
            return
        }

        if (Test-Path -Path $cnd_extract_lvl14) {
            $logBox.AppendText("Success: NDY file for level 14 found. Extracting...`n")
            .\cndtool.exe extract .\14_inf.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 14 not found. Stopping the patching.`n")
            return
        }

        if (Test-Path -Path $cnd_extract_lvl15) {
            $logBox.AppendText("Success: NDY file for level 15 found. Extracting...`n")
            .\cndtool.exe extract .\15_aet.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 15 not found. Stopping the patching.`n")
            return
        }

        if (Test-Path -Path $cnd_extract_lvl16) {
            $logBox.AppendText("Success: NDY file for level 16 found. Extracting...`n")
            .\cndtool.exe extract .\16_jep.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 16 not found. Stopping the patching.`n")
            return
        }

        if (Test-Path -Path $cnd_extract_lvl17) {
            $logBox.AppendText("Success: NDY file for level 17 found. Extracting...`n")
            .\cndtool.exe extract .\17_pru.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 17 not found. Stopping the patching.`n")
            return
        }

        if (Test-Path -Path $cnd_extract_lvl18) {
            $logBox.AppendText("Success: NDY file for level 18 found. Extracting...`n")
            .\cndtool.exe extract .\jones3dstatic.cnd
        }
        else {
            $logBox.AppendText("Error: NDY file for level 18 not found. Stopping the patching.`n")
            return
        }

        # The massive wall of extracted CND folder variables.
        $cnd_folder_extract_lvl01 = Join-Path $textBox_location.Text -ChildPath "ndy\00_cyn"
        $cnd_folder_extract_lvl02 = Join-Path $textBox_location.Text -ChildPath "ndy\01_bab"
        $cnd_folder_extract_lvl03 = Join-Path $textBox_location.Text -ChildPath "ndy\02_riv"
        $cnd_folder_extract_lvl04 = Join-Path $textBox_location.Text -ChildPath "ndy\03_shs"
        $cnd_folder_extract_lvl05 = Join-Path $textBox_location.Text -ChildPath "ndy\05_lag"
        $cnd_folder_extract_lvl06 = Join-Path $textBox_location.Text -ChildPath "ndy\06_vol"
        $cnd_folder_extract_lvl07 = Join-Path $textBox_location.Text -ChildPath "ndy\07_tem"
        $cnd_folder_extract_lvl08 = Join-Path $textBox_location.Text -ChildPath "ndy\08_teo"
        $cnd_folder_extract_lvl09 = Join-Path $textBox_location.Text -ChildPath "ndy\09_olv"
        $cnd_folder_extract_lvl10 = Join-Path $textBox_location.Text -ChildPath "ndy\10_sea"
        $cnd_folder_extract_lvl11 = Join-Path $textBox_location.Text -ChildPath "ndy\11_pyr"
        $cnd_folder_extract_lvl12 = Join-Path $textBox_location.Text -ChildPath "ndy\12_sol"
        $cnd_folder_extract_lvl13 = Join-Path $textBox_location.Text -ChildPath "ndy\13_nub"
        $cnd_folder_extract_lvl14 = Join-Path $textBox_location.Text -ChildPath "ndy\14_inf"
        $cnd_folder_extract_lvl15 = Join-Path $textBox_location.Text -ChildPath "ndy\15_aet"
        $cnd_folder_extract_lvl16 = Join-Path $textBox_location.Text -ChildPath "ndy\16_jep"
        $cnd_folder_extract_lvl17 = Join-Path $textBox_location.Text -ChildPath "ndy\17_pru"
        $cnd_folder_extract_lvl18 = Join-Path $textBox_location.Text -ChildPath "ndy\jones3dstatic"

        $ndy_extraction_subfolders = @("key", "mat", "sound")

        # Let's move them all to the root, I know one folder should be somewhere else... But hey, that will be at the end :-)
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl01 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl02 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl03 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl04 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl05 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl06 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl07 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl08 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl09 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl10 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl11 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl12 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl13 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl14 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl15 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl16 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl17 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders
        MoveFilesAndRemoveSource -sourcePath $cnd_folder_extract_lvl18 -destinationPath $destinationPath -subfolders $ndy_extraction_subfolders

        $logBox.AppendText("Success: Moved all extracted folders to the root resources folder.`n")

        # Now, let's move that Key folder.
        $key_folder_temp = Join-Path -Path $textBox_location -ChildPath "key"
        $key_folder_move_location = Join-Path -Path $textBox_location -ChildPath "3do"

        try {
            Move-Item -Path $key_folder_temp -Destination $key_folder_move_location -Force
            $logBox.AppendText("Success: the move of the key folder was successful.`n")
        }
        catch {
            $logBox.AppendText("Error: failure in moving the key folder. $($_.Exception.Message). Stopping the patching.`n")
            return
        }

        # Now we are going to do the reg edit fix.
        if ($comboBox.SelectedIndex -eq 0) {
            # CD version was selected
            $selectedKey = "HKEY_LOCAL_MACHINE\Software\LucasArts Entertainment Company LLC\Indiana Jones and the Infernal Machine\v1.0"
            Update-RegistryStartMode -registryPath $selectedKey
            $logBox.AppendText("Success: enabled the dev mode.`n")
        }
        elseif ($comboBox.SelectedIndex -eq 1) {
            # Copied from CD was selected
            $selectedKey = "HKEY_LOCAL_MACHINE\Software\LucasArts Entertainment Company LLC\Indiana Jones and the Infernal Machine\v1.0"
            $selectedKeyVirtual = "HKEY_CURRENT_USER\SOFTWARE\Classes\VirtualStore\MACHINE\SOFTWARE\WOW6432Node\LucasArts Entertainment Company LLC\Indiana Jones and the Infernal Machine\v1.0"
            Update-RegistryStartMode -registryPath $selectedKey
            Update-RegistryStartMode -registryPath $selectedKeyVirtual
            $logBox.AppendText("Success: enabled the dev mode.`n")
        }
        elseif ($comboBox.SelectedIndex -eq 2) {
            # Steam version was selected.
            $selectedKey = "HKEY_CURRENT_USER\SOFTWARE\LucasArts Entertainment Company LLC\Indiana Jones and the Infernal Machine\v1.0"
            Update-RegistryStartMode -registryPath $selectedKey
            $logBox.AppendText("Success: enabled the dev mode.`n")
        }
        elseif ($comboBox.SelectedIndex -eq 3) {
            # GOG version was selected.
            $selectedKey = "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\LucasArts Entertainment Company LLC\Indiana Jones and the Infernal Machine"
            Update-RegistryStartMode -registryPath $selectedKey
            $logBox.AppendText("Success: enabled the dev mode.`n")
        }

        # TODO: installing the first custom level?
    })

# Add the TableLayoutPanel to the form
$form.Controls.Add($tableLayoutPanel)

# Display the form
$form.Add_Shown({ $form.Activate() })
[System.Windows.Forms.Application]::Run($form)