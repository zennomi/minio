# MinIO with Console Docker Setup

This Docker Compose setup provides a complete MinIO object storage server with the Console admin UI for easy management.

## Overview

This setup includes:

- **MinIO Server**: S3-compatible object storage server
- **MinIO Console**: Graphical admin management browser UI for MinIO

## Prerequisites

- Docker and Docker Compose installed on your system
- MinIO Client (`mc`) installed (for initial setup)

## Configuration

Before starting the services, configure your credentials in the `.env` file:

1. **Copy the example file:**

   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` and set your credentials:**

   ```bash
   # MinIO Root Credentials
   MINIO_ROOT_USER=your-access-key
   MINIO_ROOT_PASSWORD=your-secure-password

   # Console User Password (leave empty to auto-generate)
   CONSOLE_PASSWORD=
   ```

   ⚠️ **Important**:

   - Change the default MinIO root credentials in production!
   - The `.env` file is excluded from git (see `.gitignore`)
   - If `CONSOLE_PASSWORD` is left empty, a secure random password will be generated

## Quick Start

1. **Start the services:**

   ```bash
   docker-compose up -d
   ```

   The setup script will automatically run and create the console user with admin privileges. Check the logs to see the generated password:

   ```bash
   docker-compose logs setup
   ```

2. **Access the services:**

   - MinIO API: http://localhost:9000
   - Console Admin UI: http://localhost:9090

3. **Credentials:**

   - **MinIO Root**: Configured in `.env` file
   - **Console User**:
     - Access Key: `console`
     - Secret Key: Check setup logs or `/setup/console-password.txt` file (or set in `.env` as `CONSOLE_PASSWORD`)

## Automated Setup

The setup process is **fully automated**! When you run `docker-compose up -d`, a setup service will:

1. Wait for MinIO to be ready
2. Create a `console` user with admin privileges
3. Generate a secure random password
4. Create and attach the admin policy

### Retrieving Console Password

The console user password is automatically generated. You can retrieve it in several ways:

**Option 1: Check setup logs**

```bash
docker-compose logs setup | grep "Secret Key"
```

**Option 2: Check password file** (if running in Docker)

```bash
cat setup/console-password.txt
```

**Option 3: Set custom password** (before starting)

```bash
export CONSOLE_PASSWORD=your-secure-password
docker-compose up -d
```

**Option 4: Set in `.env` file** (recommended)

Edit `.env` and set `CONSOLE_PASSWORD=your-secure-password`, then run `docker-compose up -d`

## Manual Setup (Alternative)

If you prefer to set up the console user manually, you have two options:

### Option A: Run the Setup Script Manually

The `setup-console.sh` script can be run directly on your host machine (requires `mc` to be installed):

```bash
./setup-console.sh
```

You can customize the setup by setting environment variables:

```bash
export MINIO_ENDPOINT=http://localhost:9000
export MINIO_ROOT_USER=minioadmin
export MINIO_ROOT_PASSWORD=minioadmin
export CONSOLE_USER=console
export CONSOLE_PASSWORD=your-custom-password
./setup-console.sh
```

### Option B: Manual Setup Using mc Commands

### Step 1: Install MinIO Client (mc)

If you don't have `mc` installed, download it from [MinIO Client Downloads](https://min.io/docs/minio/linux/reference/minio-mc.html#install-mc).

### Step 2: Configure mc to connect to your MinIO server

```bash
mc alias set myminio http://localhost:9000 minioadmin minioadmin
```

### Step 3: Create a console user

```bash
mc admin user add myminio console <your-secret-key>
```

Replace `<your-secret-key>` with a secure password.

### Step 4: Create admin policy

Create a file named `admin.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": ["admin:*"],
      "Effect": "Allow",
      "Sid": ""
    },
    {
      "Action": ["s3:*"],
      "Effect": "Allow",
      "Resource": ["arn:aws:s3:::*"],
      "Sid": ""
    }
  ]
}
```

### Step 5: Create and attach the policy

```bash
mc admin policy create myminio consoleAdmin admin.json
mc admin policy attach myminio consoleAdmin --user=console
```

### Step 6: Login to Console

Now you can access the Console Admin UI at http://localhost:9090 and login with:

- Access Key: `console`
- Secret Key: `<your-secret-key>` (the one you set in Step 3)

## Service Details

### MinIO Server

- **Container**: `minio-server`
- **Image**: `minio/minio:latest`
- **Ports**:
  - `9000`: API endpoint
- **Data Volume**: `./minio-data` (persisted locally)
- **Environment Variables**:
  - `MINIO_ROOT_USER`: Root access key
  - `MINIO_ROOT_PASSWORD`: Root secret key

### Setup Service

- **Container**: `minio-setup`
- **Image**: `minio/mc:latest`
- **Purpose**: Automatically creates console user and admin policy
- **Restart Policy**: `no` (runs once and exits)
- **Environment Variables**:
  - `MINIO_HOST`: MinIO service hostname (default: `minio`)
  - `MINIO_ENDPOINT`: Full MinIO endpoint URL
  - `MINIO_ROOT_USER`: Root access key
  - `MINIO_ROOT_PASSWORD`: Root secret key
  - `CONSOLE_USER`: Console username (default: `console`)
  - `CONSOLE_PASSWORD`: Console password (auto-generated if not set)

### Console Admin UI

- **Container**: `minio-console`
- **Image**: `ghcr.io/georgmangold/console`
- **Port**: `9090`
- **Environment Variables**:
  - `CONSOLE_MINIO_SERVER`: MinIO server URL (internal Docker network)
  - `CONSOLE_MINIO_REGION`: (Optional) Set if your MinIO region differs from `us-east-1`

## Configuration

### Changing Default Credentials

Edit the `.env` file and update the values:

```bash
MINIO_ROOT_USER=your-access-key
MINIO_ROOT_PASSWORD=your-secret-key
CONSOLE_PASSWORD=your-console-password
```

The `docker-compose.yml` file automatically reads these values from the `.env` file.

### Changing Ports

To change the exposed ports, modify the port mappings in `docker-compose.yml`:

```yaml
ports:
  - "YOUR_PORT:9000" # MinIO API
  - "YOUR_PORT:9090" # Console Admin UI
```

### Custom Region

If your MinIO server uses a region other than `us-east-1`, add to the console service:

```yaml
environment:
  CONSOLE_MINIO_SERVER: http://minio:9000
  CONSOLE_MINIO_REGION: your-region
```

## Data Persistence

All MinIO data is stored in the `./minio-data` directory, which is mounted as a volume. This ensures your data persists even if containers are removed.

## Stopping Services

```bash
docker-compose down
```

To remove volumes (⚠️ **deletes all data**):

```bash
docker-compose down -v
```

## Troubleshooting

### Console can't connect to MinIO

- Ensure both containers are running: `docker-compose ps`
- Check console logs: `docker-compose logs console`
- Verify `CONSOLE_MINIO_SERVER` is set correctly

### Can't login to Console

- Make sure you've created the console user and attached the admin policy (see "Setting Up Console User" above)
- Verify credentials are correct

### Port already in use

- Change the port mappings in `docker-compose.yml`
- Or stop the service using the port: `lsof -ti:PORT | xargs kill`

## References

- [MinIO Documentation](https://min.io/docs)
- [Console GitHub Repository](https://github.com/georgmangold/console)
- [MinIO Client (mc) Documentation](https://min.io/docs/minio/linux/reference/minio-mc.html)

## License

This setup uses:

- MinIO (AGPL-3.0)
- Console (AGPL-3.0)
