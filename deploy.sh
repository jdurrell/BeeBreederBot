#!/usr/bin/bash

# This script can be used to deploy changes quickly to a world without an internet card.
# It likely depends on the programs being stopped in-world first before copying.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

SAVE_FOLDER=$(<"$SCRIPT_DIR/savefolderpath.txt")
SERVER_ID=$(<"$SCRIPT_DIR/serverid.txt")
ROBOT_ID=$(<"$SCRIPT_DIR/robotid.txt")

# Copy server files to server.
SERVER_DEST=$(echo $SAVE_FOLDER/opencomputers/$SERVER_ID/home/BeeBreederBot/)
echo "Copying server files to $SERVER_DEST"
cp "$SCRIPT_DIR"/BeeServer/* "$SERVER_DEST/BeeServer/"
cp "$SCRIPT_DIR"/Shared/* "$SERVER_DEST/Shared"

# Copy robot files to robot.
ROBOT_DEST=$(echo $SAVE_FOLDER/opencomputers/$ROBOT_ID/home/BeeBreederBot/)
echo "Copying robot files to $ROBOT_DEST"
cp "$SCRIPT_DIR"/BeekeeperBot/* "$ROBOT_DEST/BeekeeperBot"
cp "$SCRIPT_DIR"/Shared/* "$ROBOT_DEST/Shared"
