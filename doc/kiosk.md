# Emailing sign in links

Passwordless authentication is basically auth but you ask for everything else except for a password.
The goal is to reduce workload of the poor kiosk staff member signing people in and out when they don't have their rfid card on them.

Users approach the kiosk, enter their email, and wait. We give no indication of if the email exists, and if it is a sign in or sign out link.

Once a user clicks on the link we show a confirmation on that, and create a lab session for the user. On sign out, enter email again and you'll be signed out by yourself.

page has a special layout with no links to prevent navigating away, and is designed with firefox kiosk mode in mind. Android sucks and doesn't have a decent kiosk mode

lab sessions are created when users tap in. They have a sign in time, and a sign out time of six hours from now. When users tap out, the last lab session is updated to have a correct sign out time. staff_dashboard does a weird thing with certifications, I don't know if we have to do that too.

## The Kiosk Controller

The kiosk requires a staff or admin login to access, because having it exposed to the internet means anyone can put curl in a loop and spam people's emails the login link

The controller sends a sign link, people click on the link, and they're signed in or out of a space.

## Signing a login link

We email a link to a user that contains the username, the expiry date, the space, and a combination of all, signed with a private key. a bit like the 'forgot password' email

Maybe also ask for user sign in before, but that might increase 'friction' or whatever and make users give up

Now i'm not sure if encrypting username+expiry_date+salt is good enough, but that's what https://security.stackexchange.com/questions/177643/is-emailing-sign-in-links-bad-practice recommends and we all know the internet is never wrong :^)

## One time passwords

https://security.stackexchange.com/questions/252585/security-of-email-otp-authentication

This is probably a simpler way, similar to how my bank does it. We send an OTP valid for 10 mins, user clicks on the link and it submits the OTP authenticating with the server. Downside is that the OTP will be valid for the full 10 mins, emails are 'slow' delivery, and email DDoS is still a risk unless we rate limit something down the chain.

## Simple way

Users simply type in an email and choose if they want sign in or sign out of space. We test email, if exists then we sign in. This would be secure because only staff can access the page, it would be locked down in kiosk mode on the desk inside the space physically.

However, because people can use others' emails, or mistype emails. Not an issue if we show confirmation? Additionally, uottawa emails are rather predictable and we don't want to dox students. Definitely show username and not the full name.
