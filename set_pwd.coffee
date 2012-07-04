db = require("redis").createClient()
bcrypt = require 'bcrypt'

set_pwd = (partner, pwd) ->
    salt = bcrypt.genSaltSync(10)
    hash = bcrypt.hashSync(pwd, salt)
    db.hset "partner.creds.#{partner}", 'hsecret', hash, (err, reply) ->
        if err 
            console.log err.stack
        else
            console.log 'Password successfully set!'
        process.exit()

partner = process.argv[2]
pwd = process.argv[3]
if partner and pwd 
    set_pwd(partner, pwd)
else 
    console.log """Usage:
    $ node set_pwd.js <partner_name> <new_partner_password>
    """
    process.exit()
