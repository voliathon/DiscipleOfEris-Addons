# FastFollow for Windower 4

## Description

FastFollow is a Windower 4 addon that enhances the in-game follow functionality, making it smoother and more reliable for multi-boxing. It uses inter-process communication (IPC) to synchronize character movements, ensuring that your characters stay together without the jerky movements of the default follow command.

## Features

* **Smooth Following:** Characters will follow the leader smoothly, maintaining a consistent distance.
* **Automatic Pausing:** Following is automatically paused when a character performs actions like casting a spell or using an item, preventing interruptions.
* **Distance Display:** An optional on-screen display shows the distance to other characters in your group.
* **Cross-Character Communication:** Commands can be sent from one character to control the entire group, making it easy to start and stop following.
* **Automatic Zoning:** Followers will automatically zone after the leader.

## Commands

The addon can be controlled with the `/fastfollow` or `/ffo` command, followed by one of the sub-commands below:

| Command                             | Description                                                                                                                              |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `follow <name>`                     | Starts following the character with the specified name.                                                                                  |
| `me` or `followme`                  | Makes all other characters with the addon loaded follow the character who issued the command.                                              |
| `stop`                              | Stops the current character from following.                                                                                              |
| `stopall`                           | Stops all characters from following.                                                                                                     |
| `pauseon <spell\|item\|dismount\|any>` | Toggles pausing on spell casting, item usage, or dismounting. Using `any` toggles all three.                                               |
| `pausedelay <seconds>`              | Sets the delay in seconds before a spell or item is used after pausing.                                                                  |
| `info [on\|off]`                      | Toggles the distance display. You can explicitly set it to `on` or `off`.                                                                  |
| `min <distance>`                    | Sets the minimum distance to maintain from the followed character. The value should be between 0.2 and 50.0.                               |

## Installation

1.  Download the addon files.
2.  Place the `FastFollow` folder inside your Windower4 `addons` folder.
3.  The folder structure should look like this: `Windower4/addons/FastFollow/FastFollow.lua`.
4.  In-game, load the addon with the command: `//lua load fastfollow`

## Configuration

The addon's settings are stored in `Windower4/addons/FastFollow/data/settings.xml`. You can manually edit this file to change the default settings.

Here is an example of the settings file:

```xml
<settings>
    <global>
        <display>
            <bg>
                <alpha>102</alpha>
                <blue>0</blue>
                <green>0</green>
                <red>0</red>
            </bg>
            <pos>
                <x>0</x>
                <y>0</y>
            </pos>
            <text>
                <alpha>255</alpha>
                <blue>255</blue>
                <font>Consolas</font>
                <green>255</green>
                <red>255</red>
                <size>10</size>
            </text>
        </display>
        <min>0.5</min>
        <show>false</show>
    </global>
</settings>