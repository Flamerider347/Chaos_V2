# Multi Instancer Guide

## When to use the Mutli Instancer
This is only really useful in one case, running the game on client isolated (from now on reffered to as restritected) networks. Restricted networks block direct client to client communication and many of the elements often used in WebRTC multiplayer connections. In any other situation, using the normal LAN mode or WebRTC (Introduced in the Sprint 2 release) will yeild better results for less effort.

## Requirements for use
The only requirements for using the multi instancer is a moderately capable host machine which has the ability to form connections on the local network. All connecting computers must be part of the same network and be able to communicate with the host machine. If this is not an option for security or practicality, multiplayer will not work on the network at all.

## Seting up the Instance
You will need to run the server_spooler.exe file to create the mutli instancer. This listens for requests to its local ip, accesed in windows using ipconfig in the terminal, and when a request is found it will create a headless server instance from the headless_server.exe file and direct the client to join the newly created server. This requires the headless_server.exe file to be stored in the same directory as the server_spooler.exe file. Both files will request permission to search for devices on the local network and both NEED this permission otherwise the the multi instancer will not work.