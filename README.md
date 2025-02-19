This is a project designed to learn zig programming language. I am implementing a tic-tac-toe game the hard way.

This game can be coded in a single function, but I have decided to implement it a "proper" way, to reflect the difficult parts of real software projects. Some key decisions for this project are the following:

- Dynamically sized allocated playing grid, represented in memory as slice of slices
- Universal event-driven game logic to allow for local multiplayer, local with AI, LAN multiplayer, and remote server
- Proper interfacing between systems for testing and different front-ends (cli, gui)
- Utilizing as few external dependencies as possible, writing basic things from scratch
- In-memory standaone tcp/websocket server

Feel free to look around and get insired by this project!

Compile with `zig 13.0`. Note that cli only works on linux as realtime input handling requires tty shenanigans.
