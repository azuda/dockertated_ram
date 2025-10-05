#!/bin/bash

# Path to the mod files directory
MOD_DIR=/data/mods

# Check if the mod files are already downloaded
if [ -d "$MOD_DIR" ] && [ "$(ls -A $MOD_DIR)" ]; then
  echo "Mod files already downloaded. Skipping download..."
else
  echo "Mod files not found. Downloading from CurseForge..."
  export MODPACK_PLATFORM=AUTO_CURSEFORGE
  export CF_API_KEY=${CF_API_KEY}
  export CF_PAGE_URL=https://www.curseforge.com/minecraft/modpacks/all-the-mods-9
fi

# Start the Minecraft server
exec /start-minecraft-final.sh
