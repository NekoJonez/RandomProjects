<h1>How to use this patcher script?</h1>

<p>For this tool, you need a <b>clean</b> install of the game. This script can't fully handle partially modded games yet, but I might improve the script for that in the future.</p> <br>
<p>At the moment, this tool requires an active internet connection to install. I might write an offline version maybe later.</p>

<h1>Steps to use:</h1>

*Note: if you know how to use a code editor, you can use your own code editor like Visual Studio or VSCode instead of the tutorial here.*

<h3>Step 1</h3>
Open your start menu and type: "Powershell ISE". It's important to open as "Administator" by either choosing it from the side menu OR by using a right-mouse click on "Windows Powershell ISE" and choose "Run as Admin". <br>
<br>
Note: <br>
Depending on your Windows install, it's possible that you also have "Windows Powershell ISE (x86)". This is the 32-bits version, which we don't really need if the 64-bits version is installed. <br>

<h3>Step 2</h3>
This step is only required when Windows doesn't allow you to run unsigned scripts. I'd recommend doing this and at the end of the patching, change the value back. So, if you can't run the script you'll have to do this step. <br>
<br>
<p>Type in the blue terminal at the bottom the following code:</p>

![image](https://github.com/user-attachments/assets/b43e08b1-723b-4ae2-9569-0c851f3f03ce)

`Set-ExecutionPolicy Unrestricted` and then press enter. You'll have to say: "Yes" if a dialogue box pops-up. If this command errors out, the error will tell you what to add. This can happen on company owned devices.<br>
To revert to the original setting after running the script, you'll have to run this code in the blue terminal and press enter: `Set-ExecutionPolicy RemoteSigned`

<h3>Step 3</h3>
You can do one of two things now. Either copy the whole script from the repo and paste it in the white area above the blue terminal. <br>
Or you can download the script and use the "File" > "Open" feature to get the script ready. Personally I prefer the second way, since that way you don't need to save the script before running it. Otherwise, it's possible that a dialogue box asking you to save the script will appear in the next step.

<h3>Step 4</h3>
Click on the green play icon to start the script.

![image](https://github.com/user-attachments/assets/e9aecdb1-54e0-47d4-a1f2-e2d78180631c)
<br>

<h3>Step 5</h3>
<p>The tool will open now.</p>

![image](https://github.com/user-attachments/assets/219bcebd-9939-4d73-bd8a-bdb04f238541)

*Note:* If you haven't opened your editor or Powershell ISE with administrator permissions, it will exit out before you even see the tool. It'll show an error message. To play certain mods/custom levels a reg key needs to be edited and that isn't possible without administrator permissions.
<br>
Enter in the text field your exact location of the Resource folder of your Indiana Jones and the Infernal Machine installation. This is a path as an example: `D:\SteamLibrary\steamapps\common\Indiana Jones and the Infernal Machine\Resource`. You can also choose to use the "Search" button to browse to the folder. A final slash at the end is not needed and will break the script.<br>
<p>In the dropdown underneath, select the version that install is. Depending if you have the game on Steam, GOG or used the original discs, the registry key required to patch is different. Please select the correct version. If you have already set the registry key to it's correct value, the script will skip this step :)</p><br>

<h3>Step 6</h3>
<p>When all values are set, click on the "Patch" button and wait for the magic to happen. If all goes well, you'll have a "Success: patching was successful." appear at the end in the logbox underneath the Patch button. If something went wrong, it's best to remove the game and reinstall it. (Or in case of GOG/Steam, remove the resource folder and verify the game files.)</p> <br>
<br>

<h1>Issues/bugs/idea's?</h1>
<p>If you encounter a problem, feel free to reach out to me. You can open a GitHub issue in this repo, ask me on Discord... The support will go as far as fixing issues with the patcher, not fixing issues caused by the patcher.</p>
