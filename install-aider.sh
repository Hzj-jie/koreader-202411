#!/bin/bash

sudo apt update && sudo apt install pipx -y
pipx install aider-chat
pipx ensurepath
