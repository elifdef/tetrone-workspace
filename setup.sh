#!/bin/bash
set -e

[ ! -d "tetrone-backend" ] && git clone git@github.com:elifdef/tetrone-backend.git
[ ! -d "tetrone-frontend" ] && git clone git@github.com:elifdef/tetrone-frontend.git
[ ! -d "tetrone-websockets" ] && git clone git@github.com:elifdef/tetrone-websockets.git

[ ! -f ".env" ] && cp .env.example .env
[ ! -f "tetrone-backend/.env" ] && cp tetrone-backend/.env.example tetrone-backend/.env
[ ! -f "tetrone-frontend/.env" ] && cp tetrone-frontend/.env.example tetrone-frontend/.env
[ ! -f "tetrone-websockets/.env" ] && cp tetrone-websockets/.env.example tetrone-websockets/.env

echo "done."