# PostgreSQL Provisioning Script

## Overview

`pg-provision.sh` is a safe, interactive Bash script for provisioning PostgreSQL users and databases with proper ownership and privileges.

It is designed to:

* Prevent accidental overwrites
* Handle existing users and databases safely
* Persist credentials locally for reuse
* Ensure correct privilege assignment for current and future objects

---

## Features

* Interactive input for user and database
* Detects existing roles and databases
* Avoids password overwrite for existing users
* Stores credentials locally (`.pg_credentials`)
* Assigns full ownership and privileges
* Applies default privileges for future tables, sequences, and functions
* Provides ready-to-use connection command
* Outputs manual recovery and cleanup commands

---

## Requirements

* PostgreSQL installed and running
* `psql` available in PATH
* Script executed with a role that has permission to:

  * Create users
  * Create databases
  * Assign ownership

---

## Usage

Make the script executable:

```bash
chmod +x pg-provision.sh
```

Run the script:

```bash
./pg-provision.sh
```

---

## Workflow

1. Prompt for database user and database name
2. Check if user exists:

   * If yes → reuse existing password from `.pg_credentials`
   * If no → create new user and generate password
3. Check if database exists:

   * If yes → warn and suggest backup/delete commands
   * If no → create database
4. Assign ownership and privileges
5. Output connection command

---

## Credential Storage

Credentials are stored locally in:

```
.pg_credentials
```

Format:

```
username:password
```

Permissions are restricted automatically:

```bash
chmod 600 .pg_credentials
```

---

## Example Output

```
👤 User:     tracking_user
🔐 Password: XXXXXXXXXXXXX
🗄️  Database: tracking_db

PGPASSWORD='XXXXXXXXXXXXX' psql -h localhost -U tracking_user -d "tracking_db"
```

---

## Important Notes

* Existing user passwords are NOT modified
* If login fails for an existing user:

```sql
ALTER USER username WITH PASSWORD 'new_password';
```

* Database deletion must be done manually:

```sql
DROP DATABASE "dbname";
```

---

## Safety Considerations

* No destructive operations are performed automatically
* Manual intervention required for:

  * Dropping users
  * Dropping databases
* Prevents accidental data loss

---

## Recommended Improvements (Optional)

* Use `.pgpass` instead of `.pg_credentials`
* Integrate with secrets manager (Vault, AWS Secrets Manager)
* Add logging for audit trail
* Add environment-based naming conventions

---

## License

MIT
