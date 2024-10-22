This is a project designed to learn zig programming language. I am implementing a tic-tac-toe game client and an http server.

This game can be coded in a single function, but I have decided to implement it a "proper" way, to reflect the difficult parts of real software projects. Some key decisions for this project are the following:

- Dynamically sized allocated playing grid, represented in memory as a 2D slice
- Universal game logic to allow for local multiplayer, local with AI, and remote game modes
- Proper interfacing between systems for testing and different front-ends (cli, gui, web)
- Utilizing as few external dependencies as possible, writing basic things from scratch
- Using a stateful game server, a with standalone stateful AI server
- Monorepo-like architecture, to learn about the build system

Feel free to look around and get insired by this project!
