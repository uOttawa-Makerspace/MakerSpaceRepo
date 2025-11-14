# Action Cable and web sockets

https://guides.rubyonrails.org/action_cable_overview.html#streams

Previously we were using Thin as a server, but that doesn't implement web
sockets. Switched to Puma. It's the default anyways. Used in staff dashboard on
card tap because uoeng server takes time to get back to us with membership
details.

Two ways to create a stream:

1. `stream_from key_name` and then `ActionCable.server.broadcast key_name, data`
2. `stream_for key_name` and then `ConcreteChannel.broadcast_to key_name, data`

`stream_for` tries to emulate `form_for` with it's model-reading capability.
