#Overview
A backup script runs after certain triggers in the background. This script reports status to files in the local paralells directory. 
If the backup is a defined status this app should use the macos notification subsystem to aleret the user.

I should have a notifications section that is on by default but i can swotch off when opening the app. e.g. a command line switch if that's possible.
Later I may make a settings config page but we'll keep it simple to start.

The switch can also act as a feature flag while i'm debuggin.

Locations and backups statis are in the 03-data* file.

