App Flows
1. Initial Sign-Up Flow
Step 1: Registration
Command: Not applicable (handled via app interface).
Inputs: Username, password, optional email, and agreement to terms.
Outcome: User account created and stored.
Step 2: Connection to Server
Command: None (handled by app).
Process: App establishes a TCP connection to the default IRC server (e.g., Libera Chat).
Step 3: Initial Registration with Server
Command: NICK <username>
Command: USER <username> 0 * :<real name>
Outcome: User is registered and the server acknowledges the connection.
2. First Time Connection to a New Server
Step 1: Server Selection
Command: None (handled by app).
Process: User selects a server from a list.
Step 2: Re-registration
Command: NICK <username>
Command: USER <username> 0 * :<real name>
Outcome: User is authenticated on the new server.
3. Joining a Channel
Step 1: Join Command
Command: JOIN #channel
Outcome: User is added to the channel and can start receiving messages.
4. Keep-Alive (Ping/Pong)
Step 1: Server Pings
Command: PING :server
Step 2: Respond to Ping
Command: PONG :server
Outcome: Connection remains active.
5. Backgrounding the App
Step 1: App Backgrounds
Process: App continues to send periodic PING and respond with PONG to keep the connection alive.
6. Leaving a Channel
Step 1: Part Command
Command: PART #channel
Outcome: User is removed from the channel and stops receiving messages.
7. Setting a Nickname
Step 1: Nick Command
Command: NICK <new_nickname>
Outcome: User’s nickname is updated on the server.
