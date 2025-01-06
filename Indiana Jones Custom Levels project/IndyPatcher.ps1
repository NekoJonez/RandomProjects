# NekoJonez presents Indiana Jones and the Infernal Machine - Automatic Patcher for custom levels.
# Based upon the work & tools by the modders over at https://github.com/Jones3D-The-Infernal-Engine/Mods/tree/main/levels/sed
# Written in PowerShell core 7.4.x. Will work with PowerShell 5.1 & 7+.
# Build 1.6.1 - 06/01/2025
# Visit my gaming blog: https://arpegi.wordpress.com

# Function to move files while skipping existing files
function MoveFilesAndRemoveSource {
    param ( [string]$sourcePath, [string]$destinationPath, [string[]]$subfolders )

    # Get subfolders within the source path
    foreach ($subfolder in $subfolders) {
        $fullSourcePath = Join-Path -Path $sourcePath -ChildPath $subfolder
        $fullDestinationPath = Join-Path -Path $destinationPath -ChildPath $subfolder

        # Check if source subfolder exists
        if (Test-Path -Path $fullSourcePath -PathType Container) {
            if (!(Test-Path -Path $fullDestinationPath -PathType Container)) { New-Item -Path $fullDestinationPath -ItemType Directory | Out-Null } # Ensure destination subfolder exists

            # Move files from source subfolder to destination subfolder
            Get-ChildItem -Path $fullSourcePath -File | ForEach-Object {
                $destinationFile = Join-Path -Path $fullDestinationPath -ChildPath $_.Name
                if (!(Test-Path -Path $destinationFile -PathType Leaf)) { Move-Item -Path $_.FullName -Destination $destinationFile -Force } # Check if file already exists in destination
            }
        }

        # TODO: Checking why it doesn't remove the folder here?
        Remove-Item -Path $fullSourcePath -Recurse -Force # Remove the source subfolder after moving its contents
    }
}

# Let's edit the reg key. We give the reg path as a parameter since it's different per edition of the game.
function Update-RegistryStartMode {
    param( [Parameter(Mandatory = $true)] [int]$selectedIndex, [Parameter(Mandatory = $true)] [bool]$EnableDevMode )

    # Determine the registry paths based on the selected index
    switch ($selectedIndex) {
        0 { $registryPaths = @("HKLM:\SOFTWARE\LucasArts Entertainment Company LLC\Indiana Jones and the Infernal Machine\v1.0") }
        1 {
            $registryPaths = @(
                "HKLM:\SOFTWARE\LucasArts Entertainment Company LLC\Indiana Jones and the Infernal Machine\v1.0",
                "HKCU:\SOFTWARE\Classes\VirtualStore\MACHINE\SOFTWARE\WOW6432Node\LucasArts Entertainment Company LLC\Indiana Jones and the Infernal Machine\v1.0"
            )
        }
        2 { $registryPaths = @("HKLM:\SOFTWARE\WOW6432Node\LucasArts Entertainment Company LLC\Indiana Jones and the Infernal Machine\v1.0") }
        3 { $registryPaths = @("HKCU:\SOFTWARE\LucasArts Entertainment Company LLC\Indiana Jones and the Infernal Machine\v1.0") }
        default { return @("Invalid selection index.") }
    }

    $results = @()
    foreach ($registryPath in $registryPaths) {
        $keyName = "Start Mode"
        $desiredValue = if ($EnableDevMode) { 2 } else { 0 }

        # Check if the registry path exists
        if (Test-Path -Path $registryPath) {
            try {
                $keyProperties = Get-ItemProperty -Path $registryPath # Get all properties of the registry key

                # Check if "Start mode" property exists and its value matches the desired value
                if ($keyProperties.PSObject.Properties.Name -contains $keyName) {
                    $currentValue = $keyProperties.$keyName
                    if ($currentValue -ne $desiredValue) {
                        Set-ItemProperty -Path $registryPath -Name $keyName -Value $desiredValue
                        $results += "The reg key existed and the DWORD had its value changed for $registryPath."
                    }
                    else {
                        $results += "The reg key existed and the DWORD was the right value for $registryPath."
                    }
                }
                else {
                    New-ItemProperty -Path $registryPath -Name $keyName -Value $desiredValue -PropertyType DWORD
                    $results += "The reg key existed and the DWORD was created for $registryPath."
                }
            }
            catch {
                $results += "Error accessing or modifying registry key: $registryPath."
            }
        }
        else {
            $results += "The reg key doesn't exist so the DWORD wasn't created for $registryPath."
        }
    }

    return $results
}

# Let's create a shortcut. Let's make a function out of this, since some AV's don't like it otherwise.
function Create-Shortcut {
    param ( [string] $ShortcutName, [string] $TargetPath, [string] $ShortcutFolderPath )

    $ShortcutFile = Join-Path $ShortcutFolderPath "$ShortcutName.lnk"
    if (!(Test-Path -Path $ShortcutFile -PathType Leaf)) {
        try {
            $WshShell = New-Object -ComObject WScript.Shell
            $Shortcut = $WshShell.CreateShortcut($ShortcutFile)
            $Shortcut.TargetPath = $TargetPath
            $Shortcut.Save()
        }
        catch {
            throw $_.Exception.Message
        }
    }
}

# Function to load paths from the text file into the ComboBox
function Load-Paths {
    param ( [ValidateSet("first", "second")] [string] $pathLoadState )

    $global:textBox_location.Items.Clear()
    if (Test-Path $textFilePath) { Get-Content $textFilePath | ForEach-Object { $global:textBox_location.Items.Add($_) | Out-Null } }

    if ($pathLoadState -eq "Second") {
        Check-Valid-Location -buttonUpdateState "control"
    }
    elseif ($pathLoadState -eq "First") {
        # We are still loading in, so no need to check the locations. Otherwise we are going to spit out errors.
    }
}

# Function to check and update the button text based on the input
function Update-ButtonText {
    $inputText = $global:textBox_location.Text
    if ($global:textBox_location.Items.Contains($inputText)) {
        $button_remember.Text = "Forget"
    }
    else {
        $button_remember.Text = "Remember"
    }
}

# This massive function installs and copies mod files to the right location for you.
function Install-Mods-Manually {
    param ( [string]$sourcePath, [string]$destinationPath )

    $subfolders = @("3do", "cog", "hi3do", "mat", "misc", "ndy", "sound") # Define the folder array we can just move.

    # Define file type to destination mappings
    $fileTypeMappings = @{
        ".key" = "3do\key"
        ".3do" = @("3do", "hi3do")
        ".mat" = "mat"
        ".bmp" = "misc"
        ".uni" = "misc"
        ".dat" = "misc"
        ".ai"  = "misc\ai"
        ".pup" = "misc\pup"
        ".snd" = "misc\snd"
        ".spr" = "misc\spr"
        ".ndy" = "ndy"
        ".cnd" = "ndy"
        ".wav" = "sound"
        ".cog" = "cog"
    }

    # Function to move files based on their extensions to their corresponding subfolders
    function Move-FilesByType {
        param ( [string]$sourceFolderPath, [string]$destinationBasePath, [hashtable]$typeMappings )

        foreach ($mapping in $typeMappings.GetEnumerator()) {
            $fileExtension = $mapping.Key
            $destinationSubfolders = $mapping.Value

            if (!($destinationSubfolders -is [System.Collections.IEnumerable])) { $destinationSubfolders = @($destinationSubfolders) } # Ensure destination subfolders are handled as an array

            $filesToMove = Get-ChildItem -Path $sourceFolderPath -Recurse -File -Filter "*$fileExtension" # Find all files with the current extension
            if ($filesToMove.Count -gt 0) {
                foreach ($destFolder in $destinationSubfolders) {
                    $destinationPath = Join-Path -Path $destinationBasePath -ChildPath $destFolder
                    if (!(Test-Path -Path $destinationPath -PathType Container)) { New-Item -Path $destinationPath -ItemType Directory | Out-Null }

                    foreach ($file in $filesToMove) {
                        $destFilePath = Join-Path -Path $destinationPath -ChildPath $file.Name
                        if ($fileExtension -eq ".3do") {
                            if ($destFolder -eq "3do") {
                                Copy-Item -Path $file.FullName -Destination $destFilePath -Force # Special handling for .3do files: Copy to "3do" folder
                            }
                            elseif ($destFolder -eq "hi3do") {
                                Move-Item -Path $file.FullName -Destination $destFilePath -Force # Special handling for .3do files: Move to "hi3do" folder
                            }
                        }
                        else {
                            Move-Item -Path $file.FullName -Destination $destFilePath -Force # Move other files and overwrite if they already exist
                        }
                    }
                }
            }
        }
    }

    # Function to move the contents of the target subfolder to the destination subfolder
    function Move-SubfolderContents {
        param ( [string]$sourcePath, [string]$destinationPath )

        try {
            if (!(Test-Path -Path $destinationPath -PathType Container)) { New-Item -Path $destinationPath -ItemType Directory | Out-Null } # Ensure the destination path exists
            Get-ChildItem -Path $sourcePath -Recurse | Move-Item -Destination $destinationPath -Force # Move the contents of the source subfolder to the destination subfolder
        }
        catch {
            Write-Host "Error moving contents from $sourcePath to $($destinationPath): $_"
        }
    }

    # Iterate through each specified subfolder and move contents if found in the target folder
    foreach ($subfolder in $subfolders) {
        $sourceSubfolderPath = Join-Path -Path $sourcePath -ChildPath $subfolder
        $destinationSubfolderPath = Join-Path -Path $destinationPath -ChildPath $subfolder
        if (Test-Path -Path $sourceSubfolderPath -PathType Container) { Move-SubfolderContents -sourcePath $sourceSubfolderPath -destinationPath $destinationSubfolderPath }
    }

    Move-FilesByType -sourceFolderPath $sourcePath -destinationBasePath $destinationPath -typeMappings $fileTypeMappings # Move files based on their types
}

# Let's update the buttons on the form.
function Check-Valid-Location {
    param ( [ValidateSet("control", "disable")] [string] $buttonUpdateState )

    if ($buttonUpdateState -eq "control") {
        $valid_path.$null

        # Check if the textBox_location has a value
        if (!($global:textBox_location.Text)) {
            $valid_path = "false"
        }
        else {
            $valid_path = Join-Path -Path $global:textBox_location.Text -ChildPath "Indy3D.exe"
        }

        # Enable or disable buttons based on the existence of the file
        if (Test-Path -Path $valid_path) {
            $global:textBox_location.Enabled = $true
            $button_location.Enabled = $true
            $button_remember.Enabled = $true
            $button_open.Enabled = $true
            $button_modinstall_folder.Enabled = $true
            $button_modinstall_zip.Enabled = $true
            $comboBox.Enabled = $true
            $button_enable_dev.Enabled = $true
            $button_disable_dev.Enabled = $true
            $button_patch.Enabled = $true
            $button_unpatch.Enabled = $true
            $button_shortcut.Enabled = $true
        }
        else {
            $button_modinstall_folder.Enabled = $false
            $button_modinstall_zip.Enabled = $false
            $comboBox.Enabled = $false
            $button_enable_dev.Enabled = $false
            $button_disable_dev.Enabled = $false
            $button_patch.Enabled = $false
            $button_unpatch.Enabled = $false
            $button_shortcut.Enabled = $false
        }
    }
    elseif ($buttonUpdateState -eq "disable") {
        # Let's disable those buttons.
        $global:textBox_location.Enabled = $false
        $button_location.Enabled = $false
        $button_remember.Enabled = $false
        $button_open.Enabled = $false
        $button_modinstall_folder.Enabled = $false
        $button_modinstall_zip.Enabled = $false
        $comboBox.Enabled = $false
        $button_enable_dev.Enabled = $false
        $button_disable_dev.Enabled = $false
        $button_patch.Enabled = $false
        $button_unpatch.Enabled = $false
        $button_shortcut.Enabled = $false
    }
}

Add-Type -AssemblyName System.Windows.Forms # Let's show a form on screen.
$title = "Indiana Jones and the Infernal Machine - Mod patcher" # This is the title.

# Let's exit when we don't have admin permissions, since we need to have them to edit registry.
if (!(New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    [System.Windows.Forms.MessageBox]::Show("This script needs to be run as administrator. Since the patch needs to change a reg key, and you can't do that without admin permissions.", $title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    exit
}

# Create the form to show on screen.
$form = New-Object System.Windows.Forms.Form
$form.Text = $title
$form.Size = New-Object System.Drawing.Size(1000, 760)
$form.StartPosition = "CenterScreen"

# Let's create column styles.
$columnStyle1_location = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 90)
$columnStyle2_location = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 10)
$columnStyle1_modinstall = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)
$columnStyle2_modinstall = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)
$columnStyle1_RegKey = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33)
$columnStyle2_RegKey = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33)
$columnStyle3_RegKey = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33)

# Create the TableLayoutPanel, so that it's better visually and I don't have to guess their location.
$tableLayoutPanel = New-Object System.Windows.Forms.TableLayoutPanel
$tableLayoutPanel.RowCount = 12
$tableLayoutPanel.ColumnCount = 1
$tableLayoutPanel.Dock = [System.Windows.Forms.DockStyle]::Fill

# Create a label for the install location
$label_location = New-Object System.Windows.Forms.Label
$label_location.Text = "Enter your resources location:"
$label_location.AutoSize = $true
$label_location.Dock = [System.Windows.Forms.DockStyle]::Fill
$label_location.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$tableLayoutPanel.Controls.Add($label_location)

# For the location area.
$tableLayoutPanelLocation = New-Object System.Windows.Forms.TableLayoutPanel
$tableLayoutPanelLocation.Dock = [System.Windows.Forms.DockStyle]::Fill
$tableLayoutPanelLocation.RowCount = 1
$tableLayoutPanelLocation.ColumnCount = 4
$tableLayoutPanelLocation.Height = 30
$tableLayoutPanelLocation.ColumnStyles.Add($columnStyle1_location) | Out-Null
$tableLayoutPanelLocation.ColumnStyles.Add($columnStyle2_location) | Out-Null
$tableLayoutPanel.Controls.Add($tableLayoutPanelLocation)

# Create a text box for user input
$global:textBox_location = New-Object System.Windows.Forms.ComboBox
$global:textBox_location.Dock = [System.Windows.Forms.DockStyle]::Fill
$global:textBox_location.AutoSize = $true
$global:textBox_location.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
$tableLayoutPanelLocation.Controls.Add($global:textBox_location)

# Event handler for ComboBox selection
$global:textBox_location.add_SelectedIndexChanged({
        Update-ButtonText
        Check-Valid-Location -buttonUpdateState "control"
    })

# Event handler for ComboBox text input
$global:textBox_location.add_TextChanged({
        Update-ButtonText
        Check-Valid-Location -buttonUpdateState "control"
    })

# Create a button for the user to locate the resources folder
$button_location = New-Object System.Windows.Forms.Button
$button_location.Text = "Browse"
$button_location.AutoSize = $true
$button_location.Cursor = [System.Windows.Forms.Cursors]::Hand
$button_location.Add_Click({
        $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderBrowser.Description = "Select the Indiana Jones and the Infernal Machine resource folder"
        $folderBrowser.ShowNewFolderButton = $false
        if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $global:textBox_location.Text = $folderBrowser.SelectedPath }
    })
$tableLayoutPanelLocation.Controls.Add($button_location)

# Create a button for the user to remember the resources folder
$button_remember = New-Object System.Windows.Forms.Button
$button_remember.Text = "Remember"
$button_remember.AutoSize = $true
$button_remember.Cursor = [System.Windows.Forms.Cursors]::Hand
$tableLayoutPanelLocation.Controls.Add($button_remember)

$textFilePath = "Indy3DPatcherPaths.txt" # What's that textfile that saved remembered paths?

# Add the click event for the remember button. Work with an elseif here, otherwise this stinker goes from remember mode directly into forget mode.
$button_remember.Add_Click({
        if ($button_remember.Text -eq "Remember") {
            # Let's check first if we have a valid path.
            if ([string]::IsNullOrWhiteSpace($global:textBox_location.Text)) {
                [System.Windows.Forms.MessageBox]::Show("Please enter a location.", $title)
            }
            else {
                $result = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to remember this location?", $title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
                if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                    $enteredPath = $global:textBox_location.Text
                    $control_check_location = Join-Path $enteredPath -ChildPath "\Indy3D.exe"
                    $existingPaths = if (Test-Path $textFilePath) { Get-Content $textFilePath } else { @() } # Read the existing paths from the text file

                    if ($existingPaths -contains $enteredPath) {
                        [System.Windows.Forms.MessageBox]::Show("This location already exists.", $title)
                    }
                    else {
                        if (Test-Path -Path $control_check_location) {
                            try {
                                Add-Content -Path $textFilePath -Value $enteredPath # Append the entered path to the text file
                                Load-Paths -pathLoadState "Second" # Reload paths into the ComboBox
                                Check-Valid-Location -buttonUpdateState "control" # Let's check if buttons needs to be enabled or not.
                                $button_remember.Text = "Forget" # Let's automagically set this to the forget mode.
                                $logBox.AppendText("Success: Path $enteredPath is now added to the rememeber list.`n")
                            }
                            catch {
                                [System.Windows.Forms.MessageBox]::Show("An error occurred: " + $_.Exception.Message, $title)
                                Check-Valid-Location -buttonUpdateState "control" # Let's check if buttons needs to be enabled or not.
                            }
                        }
                        else {
                            [System.Windows.Forms.MessageBox]::Show("This is an invalid resource path. It won't be remembered.", $title)
                            Check-Valid-Location -buttonUpdateState "control" # Let's check if buttons needs to be enabled or not.
                        }
                    }
                }
            }
        }
        elseif ($button_remember.Text -eq "Forget") {
            $result = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to forget this location? This will only remove this location from the dropdown list in this tool.", $title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                $selectedPath = $global:textBox_location.SelectedItem
                if ($null -ne $selectedPath) {
                    try {
                        # Remove the selected path from the text file
                        $existingPaths = Get-Content $textFilePath
                        $updatedPaths = $existingPaths | Where-Object { $_ -ne $selectedPath }
                        Set-Content -Path $textFilePath -Value $updatedPaths # Write the updated paths back to the file

                        # Let's make sure the UI reacts correctly.
                        $global:textBox_location.Text = ""
                        Load-Paths -pathLoadState "Second" # Reload paths into the ComboBox
                        $logBox.AppendText("Success: Remembered path $selectedPath was removed from the list.`n")
                        $button_remember.Text = "Remember"
                        Check-Valid-Location -buttonUpdateState "control" # Let's check if buttons needs to be enabled or not.
                    }
                    catch {
                        [System.Windows.Forms.MessageBox]::Show("An error occurred: " + $_.Exception.Message, $title)
                    }
                }
            }
        }
    })

Load-Paths -pathLoadState "First" # If the user has paths, let's load them.

# Create a button for the user to open the resources folder
$button_open = New-Object System.Windows.Forms.Button
$button_open.Text = "Open"
$button_open.AutoSize = $true
$button_open.Cursor = [System.Windows.Forms.Cursors]::Hand
$button_open.Add_Click({
        $enteredPath = $global:textBox_location.Text
        if (!([string]::IsNullOrWhiteSpace($global:textBox_location.Text))) {
            $control_check_location = Join-Path $enteredPath -ChildPath "\Indy3D.exe"
            if (Test-Path -Path $control_check_location) { Invoke-Item -Path $enteredPath }
        }
        else {
            [System.Windows.Forms.MessageBox]::Show("An invalid path is provided, this can't be opened.", $title)
            Check-Valid-Location -buttonUpdateState "control"
        }
    })

# Create a label for the mod installing
$label_modinstall = New-Object System.Windows.Forms.Label
$label_modinstall.Text = "Install a mod via:"
$label_modinstall.AutoSize = $true
$label_modinstall.Dock = [System.Windows.Forms.DockStyle]::Fill
$label_modinstall.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$tableLayoutPanel.Controls.Add($label_modinstall)

# The table layout for installing mods.
$tableLayoutPanelModInstall = New-Object System.Windows.Forms.TableLayoutPanel
$tableLayoutPanelModInstall.Dock = [System.Windows.Forms.DockStyle]::Fill
$tableLayoutPanelModInstall.RowCount = 1
$tableLayoutPanelModInstall.ColumnCount = 2
$tableLayoutPanelModInstall.Height = 30
$tableLayoutPanelModInstall.ColumnStyles.Add($columnStyle1_modinstall) | Out-Null
$tableLayoutPanelModInstall.ColumnStyles.Add($columnStyle2_modinstall) | Out-Null
$tableLayoutPanelModInstall.Height = 30
$tableLayoutPanel.Controls.Add($tableLayoutPanelModInstall)

# With this button the user can install mods with the content of a folder.
$button_modinstall_folder = New-Object System.Windows.Forms.Button
$button_modinstall_folder.Text = "Folder"
$button_modinstall_folder.Dock = [System.Windows.Forms.DockStyle]::Fill
$button_modinstall_folder.Cursor = [System.Windows.Forms.Cursors]::Hand
$button_modinstall_folder.Add_Click({
        Check-Valid-Location -buttonUpdateState "disable"

        # Extract paths from controls
        $basePath = $global:textBox_location.Text
        $path_control = Join-Path -Path $basePath -ChildPath "Indy3D.exe"
        $extraction_path = $basePath

        # Validate base path and control path
        if (([string]::IsNullOrWhiteSpace($basePath)) -or (!(Test-Path -Path $basePath))) {
            $logbox.AppendText("Error: Invalid folder mod path selected.`n")
            Check-Valid-Location -buttonUpdateState "control"
            return
        }

        if (!(Test-Path -Path $path_control)) {
            $logbox.AppendText("Error: Invalid resource path selected.`n")
            Check-Valid-Location -buttonUpdateState "control"
            return
        }

        # Show FolderBrowserDialog to select the mod folder
        $folderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderBrowserDialog.Description = "Select a mod folder to copy"
        $folderBrowserDialog.ShowNewFolderButton = $false

        # Show the dialog and check if OK button was clicked
        if ($folderBrowserDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $sourceFolderPath = $folderBrowserDialog.SelectedPath

            # Validate source folder path
            if ([string]::IsNullOrWhiteSpace($sourceFolderPath) -or -not (Test-Path -Path $sourceFolderPath)) {
                $logbox.AppendText("Error: Invalid mod folder path provided. Provide a valid folder to copy.`n")

                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            # Copy the folder contents
            try {
                Install-Mods-Manually -sourcePath $sourceFolderPath -destinationPath $extraction_path
                $logBox.AppendText("Success: Copied the folder successfully. You can delete the original folder.`n")
                Check-Valid-Location -buttonUpdateState "control"
            }
            catch {
                $logBox.AppendText("Error: Failed to copy folder: $_`n")
                Check-Valid-Location -buttonUpdateState "control"
            }
        }
    })
$tableLayoutPanelModInstall.Controls.Add($button_modinstall_folder)

# With this button, the user can install mods via a downloaded ZIP folder.
$button_modinstall_zip = New-Object System.Windows.Forms.Button
$button_modinstall_zip.Text = "Zip"
$button_modinstall_zip.Dock = [System.Windows.Forms.DockStyle]::Fill
$button_modinstall_zip.Cursor = [System.Windows.Forms.Cursors]::Hand
$button_modinstall_zip.Add_Click({
        Check-Valid-Location -buttonUpdateState "disable"

        # Define the path to check and the initial extraction path
        $basePath = $global:textBox_location.Text
        $path_control = Join-Path -Path $basePath -ChildPath "Indy3D.exe"

        if (Test-Path -Path $path_control) {
            $tempFolder = "C:\Temp_Indy_Mod" # Create a temporary folder in a safe location
            if (!(Test-Path -Path $tempFolder)) { New-Item -Path $tempFolder -ItemType Directory | Out-Null } # Create the directory if it does not exist

            # Open file dialog for selecting a ZIP file
            $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $openFileDialog.InitialDirectory = [System.Environment]::GetFolderPath('Desktop')
            $openFileDialog.Filter = "ZIP Files (*.zip)|*.zip"
            $openFileDialog.Multiselect = $false
            $openFileDialog.Title = "Select a mod ZIP file to extract"

            # Show the dialog and check if OK button was clicked
            if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $zipFilePath = $openFileDialog.FileName

                # Validate ZIP file path
                if (([string]::IsNullOrWhiteSpace($zipFilePath)) -or (!(Test-Path -Path $zipFilePath))) {
                    $logbox.AppendText("Error: Invalid ZIP file path provided. Provide a valid ZIP file.`n")
                    Check-Valid-Location -buttonUpdateState "control"
                    return
                }

                # Extract the ZIP file contents using Expand-Archive
                try {
                    Expand-Archive -Path $zipFilePath -DestinationPath $tempFolder -Force
                    Install-Mods-Manually -sourcePath $tempFolder -destinationBasePath $basePath
                    Remove-Item -Path $tempFolder -Recurse -Force
                    $logBox.AppendText("Success: Installed the mod successfully. You can remove the zip file. It's possible that a temp folder is on the root of your C drive.`n")
                }
                catch {
                    $logBox.AppendText("Error: Failed to extract ZIP file: $_`n")
                    Check-Valid-Location -buttonUpdateState "control"
                    return
                }
            }
        }
        else {
            $logbox.AppendText("Error: Invalid resource path selected.`n")
            Check-Valid-Location -buttonUpdateState "control"
            return
        }
    })
$tableLayoutPanelModInstall.Controls.Add($button_modinstall_zip)

# Create a label for the registry key
$label_regkey = New-Object System.Windows.Forms.Label
$label_regkey.Text = "Select the version you want to patch:"
$label_regkey.AutoSize = $true
$label_regkey.Dock = [System.Windows.Forms.DockStyle]::Fill
$label_regkey.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$tableLayoutPanel.Controls.Add($label_regkey)

# Implementing a feature to only patch the registry so you can enable/disable dev mode.
# Most likely, only one column style is needed, but to make the code a bit more human understandable, I choose to add all three.
$tableLayoutPanelRegKey = New-Object System.Windows.Forms.TableLayoutPanel
$tableLayoutPanelRegKey.Dock = [System.Windows.Forms.DockStyle]::Fill
$tableLayoutPanelRegKey.RowCount = 1
$tableLayoutPanelRegKey.ColumnCount = 3
$tableLayoutPanelRegKey.Height = 30
$tableLayoutPanelRegKey.ColumnStyles.Add($columnStyle1_RegKey) | Out-Null
$tableLayoutPanelRegKey.ColumnStyles.Add($columnStyle2_RegKey) | Out-Null
$tableLayoutPanelRegKey.ColumnStyles.Add($columnStyle3_RegKey) | Out-Null
$tableLayoutPanel.Controls.Add($tableLayoutPanelRegKey)

# Create a ComboBox (dropdown box) so the reg key is easier to find later.
$comboBox = New-Object System.Windows.Forms.ComboBox
$comboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$comboBox.Items.AddRange(@("Install via original CD's", "Copied files from original CD's", "Steam version", "GOG version")) | Out-Null
$comboBox.SelectedIndex = 2  # Set default selection
$comboBox.AutoSize = $true
$comboBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$tableLayoutPanelRegKey.Controls.Add($comboBox)

# Create a button to enable the dev mode.
$button_enable_dev = New-Object System.Windows.Forms.Button
$button_enable_dev.Text = "Enable dev mode"
$button_enable_dev.Dock = [System.Windows.Forms.DockStyle]::Fill
$button_enable_dev.Cursor = [System.Windows.Forms.Cursors]::Hand
$button_enable_dev.Add_Click({
        $result = [System.Windows.Forms.MessageBox]::Show("This will patch the registry so the dev mode is enabled. Are you want to sure you want to continue?", $title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            Check-Valid-Location -buttonUpdateState "disable"
            # Now we are going to do the reg edit fix.
            $selectedIndex = $comboBox.SelectedIndex
            $enableDevMode.$null
            $enableDevMode = $true

            $returnMessages = Update-RegistryStartMode -selectedIndex $selectedIndex -EnableDevMode $enableDevMode # Call the function and store the return messages
            foreach ($message in $returnMessages) { $logBox.AppendText("$message`n") } # Display the return messages to the user

            Check-Valid-Location -buttonUpdateState "control"
        }
    })
$tableLayoutPanelRegKey.Controls.Add($button_enable_dev)

# Create a button to disable the dev mode.
$button_disable_dev = New-Object System.Windows.Forms.Button
$button_disable_dev.Text = "Disable dev mode"
$button_disable_dev.Dock = [System.Windows.Forms.DockStyle]::Fill
$button_disable_dev.Cursor = [System.Windows.Forms.Cursors]::Hand
$button_disable_dev.Add_Click({
        $result = [System.Windows.Forms.MessageBox]::Show("This will patch the registry so the dev mode is disabled. Are you sure you want to continue?", $title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            Check-Valid-Location -buttonUpdateState "disable"
            # Now we are going to do the reg edit fix.
            $selectedIndex = $comboBox.SelectedIndex
            $enableDevMode.$null
            $enableDevMode = $false

            $returnMessages = Update-RegistryStartMode -selectedIndex $selectedIndex -EnableDevMode $enableDevMode # Call the function and store the return messages

            foreach ($message in $returnMessages) { $logBox.AppendText("$message`n") } # Display the return messages to the user
            Check-Valid-Location -buttonUpdateState "control"
        }
    })
$tableLayoutPanelRegKey.Controls.Add($button_disable_dev)

# Create a button to start the patching proceess
$button_patch = New-Object System.Windows.Forms.Button
$button_patch.Text = "Patch"
$button_patch.Dock = [System.Windows.Forms.DockStyle]::Fill
$button_patch.Cursor = [System.Windows.Forms.Cursors]::Hand
$button_patch.Add_Click({
        $result = [System.Windows.Forms.MessageBox]::Show("This will start the patching process with the selected values. Are you certain? If something goes wrong, you'll have to restart the tool.", $title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            Check-Valid-Location -buttonUpdateState "disable"

            if ($global:textBox_location.Text) {
                $location_checker = Join-Path -Path $global:textBox_location.Text -ChildPath "\Indy3D.exe"
                if (!(Test-Path -Path $location_checker)) {
                    $logBox.AppendText("Error: Invalid resource path provided. Stopping pathing procedure.`n")
                    Check-Valid-Location -buttonUpdateState "control"
                    return
                }
            }
            else {
                $logBox.AppendText("Error: Invalid reesource path provided. Stopping pathing procedure.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            # Let's download the working version of the tools. I'm going to hardcode v0.10.1 here for now, since if Kovic's PR (https://github.com/smlu/Urgon/pull/11) ever gets merged,
            # later logic will need to change.
            $Tools_Temp_Path = $global:textBox_location.Text + "\urgon-windows-x86-64.zip"

            try {
                Invoke-WebRequest -Uri https://github.com/smlu/Urgon/releases/download/v0.10.1/urgon-windows-x86-64.zip -OutFile $Tools_Temp_Path
                $logBox.AppendText("Success: Tools v0.10.1 succesfully downloaded.`n")
            }
            catch {
                $logBox.AppendText("Error: Tools couldn't be downloaded. $_ . Stopping pathing procedure.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            try {
                Expand-Archive -Path $Tools_Temp_Path -DestinationPath $global:textBox_location.Text
                $logBox.AppendText("Success: Tools v0.10.1 succesfully extracted from zip file and placed in resource folder.`n")
            }
            catch {
                $logBox.AppendText("Error: Tools couldn't be extracted and moved. $_ . Stopping pathing procedure.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            Set-Location $global:textBox_location.Text # Let's go to that resource folder.

            # Let's first extract those GOB files. Since, this tool doesn't really work with extracting to the desired folder, let's move the files afterwards.
            $gob_tool_test = Join-Path $global:textBox_location.Text -ChildPath "\gobext.exe"
            $gob_extract_cd1 = Join-Path $global:textBox_location.Text -ChildPath "\CD1.gob"
            $gob_extract_cd2 = Join-Path $global:textBox_location.Text -ChildPath "\CD2.gob"
            $gob_extract_jones3d = Join-Path $global:textBox_location.Text -ChildPath "\JONES3D.gob"
            if (Test-Path -Path $gob_tool_test) {
                if (Test-Path -Path $gob_extract_cd1) {
                    $logBox.AppendText("Info: Extraction of GOB_CD1 started.`n")
                    .\gobext.exe CD1.GOB
                    $logBox.AppendText("Success: CD1.GOB successfully extracted.`n")
                }
                else {
                    $logBox.AppendText("Error: CD1.GOB was missing and wasn't extracted.`n")
                    Check-Valid-Location -buttonUpdateState "control"
                    return
                }

                if (Test-Path -Path $gob_extract_cd2) {
                    $logBox.AppendText("Info: Extraction of GOB_CD2 started.`n")
                    .\gobext.exe CD2.GOB
                    $logBox.AppendText("Success: CD2.GOB successfully extracted.`n")
                }
                else {
                    $logBox.AppendText("Error: CD2.GOB was missing and wasn't extracted.`n")
                    Check-Valid-Location -buttonUpdateState "control"
                    return
                }

                if (Test-Path -Path $gob_extract_jones3d) {
                    $logBox.AppendText("Info: Extraction of Jones3D started.`n")
                    .\gobext.exe JONES3D.GOB
                    $logBox.AppendText("Success: JONES3D.GOB successfully extracted.`n")
                }
                else {
                    $logBox.AppendText("Error: JONES3D.GOB was missing and wasn't extracted.`n")
                    Check-Valid-Location -buttonUpdateState "control"
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
            $cd1_gob_location = Join-Path $global:textBox_location.text -ChildPath "\CD1_GOB"
            $cd2_gob_location = Join-Path $global:textBox_location.text -ChildPath "\CD2_GOB"
            $jones3d_gob_location = Join-Path $global:textBox_location.text -ChildPath "\JONES3D_GOB"
            $destinationPath = $global:textBox_location.text

            # Define subfolders for each parent folder
            $cd1_and_2_subfolders = @("3do", "cog", "hi3do", "mat", "misc", "ndy")
            $jones3d_subfolders = @("3do", "cog", "mat", "misc", "ndy")

            # Let's rename the original cog folder for backup propuses.
            $cog_folder = Join-Path $global:textBox_location.text -ChildPath "\Cog"
            if (Test-Path -Path $cog_folder -PathType Container) {
                # Get the new folder name with "_backup"
                $newFolderName = [System.IO.Path]::GetFileName($cog_folder) + "_backup"
                $newFolderPath = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($cog_folder), $newFolderName)

                # Copy the original folder to a new _backup folder location
                Copy-Item -Path $cog_folder -Destination $newFolderPath -Recurse -Force
                $logBox.AppendText("Success: Made a backup of the original COG folder and named it Cog_backup.`n")
            }
            else {
                $logBox.AppendText("Warning: The original COG folder wasn't found. This could result in game issues.`n")
            }

            # Call the function for each source parent folder with respective subfolders
            MoveFilesAndRemoveSource -sourcePath $cd1_gob_location -destinationPath $destinationPath -subfolders $cd1_and_2_subfolders
            MoveFilesAndRemoveSource -sourcePath $cd2_gob_location -destinationPath $destinationPath -subfolders $cd1_and_2_subfolders
            MoveFilesAndRemoveSource -sourcePath $jones3d_gob_location -destinationPath $destinationPath -subfolders $jones3d_subfolders

            # Now, let's remove the GOB files. Since, it's going to work :-)
            $filePathsToRename = @($gob_extract_cd1, $gob_extract_cd2, $gob_extract_jones3d)
            $filePathsToRemoveFolders = @($cd1_gob_location, $cd2_gob_location, $jones3d_gob_location)

            # Let's remove the extraction folders.
            foreach ($filePathsToRemoveFolder in $filePathsToRemoveFolders) { if (Test-Path -Path $filePathsToRemoveFolder) { Remove-Item -Path $filePathsToRemoveFolder -Recurse -Force } }

            # Rename files using foreach loop, after this step 2 is done.
            foreach ($filePathToRename in $filePathsToRename) {
                if (Test-Path -Path $filePathToRename) {
                    $fileDirectory = [System.IO.Path]::GetDirectoryName($filePathToRename)
                    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePathToRename)

                    $newFileName = "$fileName.gob.bak"
                    $newFilePath = [System.IO.Path]::Combine($fileDirectory, $newFileName)

                    Rename-Item -Path $filePathToRename -NewName $newFilePath -Force
                }
            }

            $logBox.AppendText("Success: GOB files were renamed succesfully. You can remove the '_backup' if you want to reuse the standard ones.`n")

            # Now, let's move the CNDtool to it's rightful location.
            $cnd_tool_test = Join-Path $global:textBox_location.Text -ChildPath "\cndtool.exe"
            $ndy_folder_location = Join-Path $global:textBox_location.text -ChildPath "\ndy"
            if (Test-Path -Path $cnd_tool_test) {
                if (Test-Path -Path $ndy_folder_location) {
                    Move-Item -Path $cnd_tool_test -Destination $ndy_folder_location
                }
                else {
                    $logBox.AppendText("Error: NDY folder not found. Stopping the patching.`n")
                    Check-Valid-Location -buttonUpdateState "control"
                    return
                }
            }
            else {
                $logBox.AppendText("Error: CND tool not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            Set-Location $ndy_folder_location

            # The massive wall of CND variables.
            $cnd_extract_lvl01 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\00_cyn.cnd"
            $cnd_extract_lvl02 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\01_bab.cnd"
            $cnd_extract_lvl03 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\02_riv.cnd"
            $cnd_extract_lvl04 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\03_shs.cnd"
            $cnd_extract_lvl05 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\05_lag.cnd"
            $cnd_extract_lvl06 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\06_vol.cnd"
            $cnd_extract_lvl07 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\07_tem.cnd"
            $cnd_extract_lvl08 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\08_teo.cnd"
            $cnd_extract_lvl09 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\09_olv.cnd"
            $cnd_extract_lvl10 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\10_sea.cnd"
            $cnd_extract_lvl11 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\11_pyr.cnd"
            $cnd_extract_lvl12 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\12_sol.cnd"
            $cnd_extract_lvl13 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\13_nub.cnd"
            $cnd_extract_lvl14 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\14_inf.cnd"
            $cnd_extract_lvl15 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\15_aet.cnd"
            $cnd_extract_lvl16 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\16_jep.cnd"
            $cnd_extract_lvl17 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\17_pru.cnd"
            $cnd_extract_lvl18 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\jones3dstatic.cnd"

            if (Test-Path -Path $cnd_extract_lvl01) {
                $logBox.AppendText("Info: NDY file for level 01 found. Extracting...`n")
                .\cndtool.exe extract .\00_cyn.cnd
                $logBox.AppendText("Success: NDY file for level 01 extracted, moving on to the next one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 01 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            if (Test-Path -Path $cnd_extract_lvl02) {
                $logBox.AppendText("Info: NDY file for level 02 found. Extracting...`n")
                .\cndtool.exe extract .\01_bab.cnd
                $logBox.AppendText("Success: NDY file for level 02 extracted, moving on to the next one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 02 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            if (Test-Path -Path $cnd_extract_lvl03) {
                $logBox.AppendText("Info: NDY file for level 03 found. Extracting...`n")
                .\cndtool.exe extract .\02_riv.cnd
                $logBox.AppendText("Success: NDY file for level 03 extracted, moving on to the next one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 03 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            if (Test-Path -Path $cnd_extract_lvl04) {
                $logBox.AppendText("Info: NDY file for level 04 found. Extracting...`n")
                .\cndtool.exe extract .\03_shs.cnd
                $logBox.AppendText("Success: NDY file for level 04 extracted, moving on to the next one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 04 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            if (Test-Path -Path $cnd_extract_lvl05) {
                $logBox.AppendText("Info: NDY file for level 05 found. Extracting...`n")
                .\cndtool.exe extract .\05_lag.cnd
                $logBox.AppendText("Success: NDY file for level 05 extracted, moving on to the next one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 05 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            if (Test-Path -Path $cnd_extract_lvl06) {
                $logBox.AppendText("Info: NDY file for level 06 found. Extracting...`n")
                .\cndtool.exe extract .\06_vol.cnd
                $logBox.AppendText("Success: NDY file for level 06 extracted, moving on to the next one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 06 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            if (Test-Path -Path $cnd_extract_lvl07) {
                $logBox.AppendText("Info: NDY file for level 07 found. Extracting...`n")
                .\cndtool.exe extract .\07_tem.cnd
                $logBox.AppendText("Success: NDY file for level 07 extracted, moving on to the next one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 07 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            if (Test-Path -Path $cnd_extract_lvl08) {
                $logBox.AppendText("Info: NDY file for level 08 found. Extracting...`n")
                .\cndtool.exe extract .\08_teo.cnd
                $logBox.AppendText("Success: NDY file for level 08 extracted, moving on to the next one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 08 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            if (Test-Path -Path $cnd_extract_lvl09) {
                $logBox.AppendText("Info: NDY file for level 09 found. Extracting...`n")
                .\cndtool.exe extract .\09_olv.cnd
                $logBox.AppendText("Success: NDY file for level 09 extracted, moving on to the next one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 09 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            if (Test-Path -Path $cnd_extract_lvl10) {
                $logBox.AppendText("Info: NDY file for level 10 found. Extracting...`n")
                .\cndtool.exe extract .\10_sea.cnd
                $logBox.AppendText("Success: NDY file for level 10 extracted, moving on to the next one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 10 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            if (Test-Path -Path $cnd_extract_lvl11) {
                $logBox.AppendText("Info: NDY file for level 11 found. Extracting...`n")
                .\cndtool.exe extract .\11_pyr.cnd
                $logBox.AppendText("Success: NDY file for level 11 extracted, moving on to the next one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 11 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            if (Test-Path -Path $cnd_extract_lvl12) {
                $logBox.AppendText("Info: NDY file for level 12 found. Extracting...`n")
                .\cndtool.exe extract .\12_sol.cnd
                $logBox.AppendText("Success: NDY file for level 12 extracted, moving on to the next one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 12 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            if (Test-Path -Path $cnd_extract_lvl13) {
                $logBox.AppendText("Info: NDY file for level 13 found. Extracting...`n")
                .\cndtool.exe extract .\13_nub.cnd
                $logBox.AppendText("Success: NDY file for level 13 extracted, moving on to the next one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 13 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            if (Test-Path -Path $cnd_extract_lvl14) {
                $logBox.AppendText("Info: NDY file for level 14 found. Extracting...`n")
                .\cndtool.exe extract .\14_inf.cnd
                $logBox.AppendText("Success: NDY file for level 14 extracted, moving on to the next one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 14 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            if (Test-Path -Path $cnd_extract_lvl15) {
                $logBox.AppendText("Info: NDY file for level 15 found. Extracting...`n")
                .\cndtool.exe extract .\15_aet.cnd
                $logBox.AppendText("Success: NDY file for level 15 extracted, moving on to the next one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 15 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            if (Test-Path -Path $cnd_extract_lvl16) {
                $logBox.AppendText("Info: NDY file for level 16 found. Extracting...`n")
                .\cndtool.exe extract .\16_jep.cnd
                $logBox.AppendText("Success: NDY file for level 16 extracted, moving on to the next one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 16 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            if (Test-Path -Path $cnd_extract_lvl17) {
                $logBox.AppendText("Info: NDY file for level 17 found. Extracting...`n")
                .\cndtool.exe extract .\17_pru.cnd
                $logBox.AppendText("Success: NDY file for level 17 extracted, moving on to the next one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 17 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            if (Test-Path -Path $cnd_extract_lvl18) {
                $logBox.AppendText("Info: NDY file for level 18 found. Extracting...`n")
                .\cndtool.exe extract .\jones3dstatic.cnd
                $logBox.AppendText("Success: NDY file for level 18 extracted. This was the final one.`n")
            }
            else {
                $logBox.AppendText("Error: NDY file for level 18 not found. Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            # The massive wall of extracted CND folder variables.
            $cnd_folder_extract_lvl01 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\00_cyn"
            $cnd_folder_extract_lvl02 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\01_bab"
            $cnd_folder_extract_lvl03 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\02_riv"
            $cnd_folder_extract_lvl04 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\03_shs"
            $cnd_folder_extract_lvl05 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\05_lag"
            $cnd_folder_extract_lvl06 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\06_vol"
            $cnd_folder_extract_lvl07 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\07_tem"
            $cnd_folder_extract_lvl08 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\08_teo"
            $cnd_folder_extract_lvl09 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\09_olv"
            $cnd_folder_extract_lvl10 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\10_sea"
            $cnd_folder_extract_lvl11 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\11_pyr"
            $cnd_folder_extract_lvl12 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\12_sol"
            $cnd_folder_extract_lvl13 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\13_nub"
            $cnd_folder_extract_lvl14 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\14_inf"
            $cnd_folder_extract_lvl15 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\15_aet"
            $cnd_folder_extract_lvl16 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\16_jep"
            $cnd_folder_extract_lvl17 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\17_pru"
            $cnd_folder_extract_lvl18 = Join-Path $global:textBox_location.Text -ChildPath "\ndy\jones3dstatic"

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

            # Let's remove the extraction folders.
            $CNDToRemoveFolders = @($cnd_folder_extract_lvl01, $cnd_folder_extract_lvl02, $cnd_folder_extract_lvl03, $cnd_folder_extract_lvl04, $cnd_folder_extract_lvl05, $cnd_folder_extract_lvl06, $cnd_folder_extract_lvl07, $cnd_folder_extract_lvl08, $cnd_folder_extract_lvl09, $cnd_folder_extract_lvl10, $cnd_folder_extract_lvl11, $cnd_folder_extract_lvl12, $cnd_folder_extract_lvl13, $cnd_folder_extract_lvl14, $cnd_folder_extract_lvl15, $cnd_folder_extract_lvl16, $cnd_folder_extract_lvl17, $cnd_folder_extract_lvl18)
            foreach ($CNDToRemoveFolder in $CNDToRemoveFolders) { if (Test-Path -Path $CNDToRemoveFolder) { Remove-Item -Path $CNDToRemoveFolder -Recurse -Force } }

            # Now, let's move that Key folder.
            $key_folder_temp = Join-Path -Path $global:textBox_location.Text -ChildPath "\key"
            $key_folder_move_location = Join-Path -Path $global:textBox_location.Text -ChildPath "\3do"

            try {
                $logBox.AppendText("Info: moving the key folder to it's rightful location.`n")
                Move-Item -Path $key_folder_temp -Destination $key_folder_move_location -Force
                $logBox.AppendText("Success: the move of the key folder was successful.`n")
            }
            catch {
                $logBox.AppendText("Error: failure in moving the key folder. $_ . Stopping the patching.`n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }

            # Now we are going to do the reg edit fix.
            $selectedIndex = $comboBox.SelectedIndex
            $enableDevMode = $true

            $returnMessages = Update-RegistryStartMode -selectedIndex $selectedIndex -EnableDevMode $enableDevMode # Call the function and store the return messages

            foreach ($message in $returnMessages) { $logBox.AppendText("$message`n") } # Display the return messages to the user

            $dev_mode_exe_location = Join-Path $global:textBox_location.Text -ChildPath "Indy3D.exe"
            $shortcutName = "Indiana Jones and the Infernal Machine - Dev mode"
            $desktop_location = [Environment]::GetFolderPath("Desktop")

            Create-Shortcut -ShortcutName $ShortcutName -TargetPath $dev_mode_exe_location -ShortcutFolderPath $desktop_location
            $logbox.AppendText("Success: shortcut has been created.`n")

            $logBox.AppendText("Success: patching was successful.`n")
            Check-Valid-Location -buttonUpdateState "control"
        }
    })
$tableLayoutPanel.Controls.Add($button_patch)

# Create a button to undo the patch process
$button_unpatch = New-Object System.Windows.Forms.Button
$button_unpatch.Text = "Undo patch"
$button_unpatch.Dock = [System.Windows.Forms.DockStyle]::Fill
$button_unpatch.Cursor = [System.Windows.Forms.Cursors]::Hand
$button_unpatch.Add_Click({
        $result = [System.Windows.Forms.MessageBox]::Show("This will undo the patching of the game done by this script. It will undo changes in the resource folder & the registry. This will also uninstall all custom levels. Be sure the the following information is correct: the path to the resource folder and the selected version for the registry. Are you certain?", $title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            Check-Valid-Location -buttonUpdateState "disable"

            # Let's undo the renaming of the GOB files. This first array is if the user used my old version of the tool.
            $gob_backup_extract_cd1 = Join-Path $global:textBox_location.Text -ChildPath "\CD1_backup.gob"
            $gob_backup_extract_cd2 = Join-Path $global:textBox_location.Text -ChildPath "\CD2_backup.gob"
            $gob_backup_extract_jones3d = Join-Path $global:textBox_location.Text -ChildPath "\JONES3D_backup.gob"
            $fileBackupPathsToRename = @($gob_backup_extract_cd1, $gob_backup_extract_cd2, $gob_backup_extract_jones3d)

            # Let's undo the renaming of the GOB files. This second array is if the user used the new version of the tool.
            $gob_bak_extract_cd1 = Join-Path $global:textBox_location.Text -ChildPath "\CD1.gob.bak"
            $gob_bak_extract_cd2 = Join-Path $global:textBox_location.Text -ChildPath "\CD2.gob.bak"
            $gob_bak_extract_jones3d = Join-Path $global:textBox_location.Text -ChildPath "\JONES3D.gob.bak"
            $fileBakPathsToRename = @($gob_bak_extract_cd1, $gob_bak_extract_cd2, $gob_bak_extract_jones3d)

            $filePathsToRename = $fileBackupPathsToRename + $fileBakPathsToRename # Combine both arrays for the renaming process
            foreach ($filePathToRename in $filePathsToRename) {
                if (Test-Path -Path $filePathToRename) {
                    $fileDirectory = [System.IO.Path]::GetDirectoryName($filePathToRename)
                    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePathToRename)
                    $fileExtension = [System.IO.Path]::GetExtension($filePathToRename)

                    if ($fileName.EndsWith("_backup")) {
                        $newFileName = $fileName.Substring(0, $fileName.Length - 7) + $fileExtension # Remove "_backup" from the filename
                    }
                    elseif ($fileExtension -eq ".bak") {
                        $newFileName = $fileName + ".gob" # Change the .bak extension to .gob
                    }
                    else {
                        continue
                    }

                    $newFilePath = [System.IO.Path]::Combine($fileDirectory, $newFileName)
                    Rename-Item -Path $filePathToRename -NewName $newFilePath -Force
                }
                else {
                    $logBox.AppendText("Failure: The GOB file $($filePathToRename) doesn't exist. Can't complete the process. Exiting...`n")
                    Check-Valid-Location -buttonUpdateState "control"
                    return
                }
            }

            $logBox.AppendText("Success: reverted the backup GOB files to it's original state.`n")

            $cog_backup_folder = Join-Path $global:textBox_location.text -ChildPath "\Cog_backup"
            $cog_mod_folder = Join-Path $global:textBox_location.text -ChildPath "\Cog"
            if (Test-Path -Path $cog_backup_folder -PathType Container) {
                Remove-Item -Path $cog_mod_folder -Recurse -Force
                Rename-Item -Path $cog_backup_folder -NewName "Cog" -Force
                $logBox.AppendText("Success: Reverted the backup Cog folder to it's original state.`n")
            }
            else {
                $logBox.AppendText("Warning: The original COG folder wasn't found. This could result in game issues.`n")
            }

            $3do_mod_folder = Join-Path -Path $global:textBox_location.Text -ChildPath "\3do"
            $hi3do_mod_folder = Join-Path -Path $global:textBox_location.Text -ChildPath "\hi3do"
            $mat_mod_folder = Join-Path -Path $global:textBox_location.Text -ChildPath "\mat"
            $misc_mod_folder = Join-Path -Path $global:textBox_location.Text -ChildPath "\misc"
            $ndy_mod_folder = Join-Path -Path $global:textBox_location.Text -ChildPath "\ndy"
            $sound_mod_folder = Join-Path -Path $global:textBox_location.Text -ChildPath "\sound"
            $ModFoldersToRemove = @($3do_mod_folder, $hi3do_mod_folder, $mat_mod_folder, $misc_mod_folder, $ndy_mod_folder, $sound_mod_folder)
            foreach ($ModFolderToRemove in $ModFoldersToRemove) { if (Test-Path -Path $ModFolderToRemove) { Remove-Item -Path $ModFolderToRemove -Recurse -Force } }

            $logBox.AppendText("Success: Removed all mod extracted folders.`n")

            $gobext_tool = Join-Path $global:textBox_location.Text -ChildPath "gobext.exe"
            $ma_tool = Join-Path $global:textBox_location.Text -ChildPath "matool.exe"
            $Tools_Temp_Path = $global:textBox_location.Text + "\urgon-windows-x86-64.zip"
            $ToolsToClean = @($gobext_tool, $ma_tool, $Tools_Temp_Path)
            foreach ($ToolToClean in $ToolsToClean) { if (Test-Path -Path $ToolToClean) { Remove-Item -Path $ToolToClean -Recurse -Force } }

            # Now we are going to do the reg edit fix.
            $selectedIndex = $comboBox.SelectedIndex
            $enableDevMode = $false

            $returnMessages = Update-RegistryStartMode -selectedIndex $selectedIndex -EnableDevMode $enableDevMode # Call the function and store the return messages

            foreach ($message in $returnMessages) { $logBox.AppendText("$message`n") } # Display the return messages to the user

            $logBox.AppendText("Success: Finished undoing the patch.`n")
            Check-Valid-Location -buttonUpdateState "control"
        }
    })
$tableLayoutPanel.Controls.Add($button_unpatch)

# Create a text box for logs
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$logBox.Height = 400
$logBox.Width = ($form.Width - 20)
$logBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$logBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$tableLayoutPanel.Controls.Add($logBox)

# To avoid big buttons, let's do this.
$tableLayoutBottomButtons = New-Object System.Windows.Forms.TableLayoutPanel
$tableLayoutBottomButtons.Dock = [System.Windows.Forms.DockStyle]::Fill
$tableLayoutBottomButtons.RowCount = 2
$tableLayoutBottomButtons.ColumnCount = 1
$tableLayoutBottomButtons.Height = 60
$tableLayoutPanel.Controls.Add($tableLayoutBottomButtons)

# Create a button so a shortcut can be created for the game in dev mode.
$button_shortcut = New-Object System.Windows.Forms.Button
$button_shortcut.Text = "Create shortcut for dev mode"
$button_shortcut.Dock = [System.Windows.Forms.DockStyle]::Fill
$button_shortcut.Cursor = [System.Windows.Forms.Cursors]::Hand
$button_shortcut.Add_Click({
        $result = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to create a shortcut to the game on your desktop? This shortcut will open in dev mode if you patched your game or you enabled dev mode. You will need to provide the path to your resource folder of the game install!", $title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            Check-Valid-Location -buttonUpdateState "disable"

            # Let's create said shortcut.
            if ($null -eq $global:textBox_location.Text) {
                $logBox.AppendText("Error: no valid resource path provided. `n")
                Check-Valid-Location -buttonUpdateState "control"
                return
            }
            else {
                $dev_mode_exe_location = $global:textBox_location.Text + "\Indy3D.exe"
                if (Test-Path -Path $dev_mode_exe_location) {
                    $shortcutName = "Indiana Jones and the Infernal Machine - Dev mode"
                    $desktop_location = [Environment]::GetFolderPath("Desktop")

                    Create-Shortcut -ShortcutName $ShortcutName -TargetPath $dev_mode_exe_location -ShortcutFolderPath $desktop_location
                    $logbox.AppendText("Success: shortcut has been created.`n")
                    Check-Valid-Location -buttonUpdateState "control"
                }
                else {
                    $logBox.AppendText("Error: no valid game executable found in the resource folder.`n")
                    Check-Valid-Location -buttonUpdateState "control"
                    return
                }
            }
        }
    })
$tableLayoutBottomButtons.Controls.Add($button_shortcut)

# Create an exit button.
$button_exit = New-Object System.Windows.Forms.Button
$button_exit.Text = "Exit tool"
$button_exit.Dock = [System.Windows.Forms.DockStyle]::Fill
$button_exit.Cursor = [System.Windows.Forms.Cursors]::Hand
$button_exit.Add_Click({
        $result = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to exit?", $title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) { $form.Close() }
    })
$tableLayoutBottomButtons.Controls.Add($button_exit)

# Create the credit label
$label_credit = New-Object System.Windows.Forms.Label
$label_credit.Text = "$title - v1.6.1 - Released 06/01/2025"
$label_credit.AutoSize = $true
$label_credit.Dock = [System.Windows.Forms.DockStyle]::Fill
$label_credit.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$label_credit.ForeColor = [System.Drawing.Color]::Blue
$label_credit.Cursor = [System.Windows.Forms.Cursors]::Hand
$label_credit.Add_Click({ Start-Process "https://github.com/NekoJonez/RandomProjects/releases" })
$tableLayoutPanel.Controls.Add($label_credit)

Check-Valid-Location -buttonUpdateState "control" # Now that all is drawn, let's check the buttons for the first time.
$form.Controls.Add($tableLayoutPanel) # Add the TableLayoutPanel to the form
$form.Add_Shown({ $form.Activate() })
[System.Windows.Forms.Application]::Run($form) # Display the form