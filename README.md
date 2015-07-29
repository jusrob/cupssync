# cupssync
Script to keep two (or more) cups servers printer configs the same

This assumes that you choose one server as the "master" server that all lpadmin commands will be ran on.  You then run the script on the master server and it keeps all other cups servers printer configs the same.

I put it in crontab to run every 10mins, but could run via jenkins or your prefered scheudler as well.

This could use alot of improvements, but solved a problem i had very well at the time.  Feel free to fork or suggest changes.
