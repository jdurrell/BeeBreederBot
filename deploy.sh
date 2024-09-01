#!/usr/bin/bash

# This script can be used to deploy changes quickly to a world without an internet card.
# It likely depends on the programs being stopped in-world first before copying.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

SAVE_FOLDER=$(<$SCRIPT_DIR/savefolderpath.txt) | tr -d '\n'
SERVER_ID=$(<$SCRIPT_DIR/serverid.txt) | tr -d '\n'
ROBOT_ID=%(<$SCRIPT_DIR/robotid.txt) | tr -d '\n'



# Copy server files to server.
$SERVER_DEST="$SAVE_FOLDER/opencomputers/$SERVER_ID/home/BeeBreederBot"
cp $SCRIPT_DIR/BeeServer/* $SERVER_DEST
cp $SCRIPT_DIR/Shared/* $SERVER_DEST

# Copy robot files to robot.
$ROBOT_DEST="$SAVE_FOLDER/opencomputers/$ROBOT_ID/home/BeeBreederBot"
cp $SCRIPT_DIR/BeeBot/* $ROBOT_DEST
cp $SCRIPT_DIR/Shared/* $ROBOT_DEST
