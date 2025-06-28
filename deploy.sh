#!/usr/bin/bash

# This script can be used to deploy changes quickly to a world without an internet card.
# It likely depends on the programs being stopped in-world first before copying.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

SAVE_FOLDER=$(<"$SCRIPT_DIR/savefolderpath.txt")
SERVER_ID=$(<"$SCRIPT_DIR/serverid.txt")
ROBOT_ID=$(<"$SCRIPT_DIR/robotid.txt")
ANALYZER_ID=$(<"$SCRIPT_DIR/analyzerid.txt")

# Copy server files to server.
SERVER_DEST=$(echo $SAVE_FOLDER/opencomputers/$SERVER_ID/home/BeeBreederBot)
mkdir -p "$SERVER_DEST"
echo "Copying server files to $SERVER_DEST"
cp -r "$SCRIPT_DIR"/BeeServer "$SERVER_DEST"
cp -r "$SCRIPT_DIR"/Shared "$SERVER_DEST"

# Copy robot files to robot.
ROBOT_DEST=$(echo $SAVE_FOLDER/opencomputers/$ROBOT_ID/home/BeeBreederBot)
echo "Copying robot files to $ROBOT_DEST"
mkdir -p "$ROBOT_DEST"
cp -r "$SCRIPT_DIR"/BeekeeperBot "$ROBOT_DEST"
cp -r "$SCRIPT_DIR"/Shared "$ROBOT_DEST"

# Copy analyzer files to analyzer bot.
ANALYZER_DEST=$(echo $SAVE_FOLDER/opencomputers/$ANALYZER_ID/home/BeeBreederBot)
echo "Copying analyzer files to $ANALYZER_DEST"
mkdir -p "$ANALYZER_DEST"
mkdir -p "$ANALYZER_DEST/Shared"
cp -r "$SCRIPT_DIR"/AnalyzerBot "$ANALYZER_DEST"
cp "$SCRIPT_DIR"/Shared/Shared.lua "$ANALYZER_DEST/Shared"
cp "$SCRIPT_DIR"/Shared/FieldDebug.lua "$ANALYZER_DEST/Shared"
