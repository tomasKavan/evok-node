# HW Test rig service

HW test rig is a set of hardware for physical testing of `evok-node` library. The service is a main controlling tool to setup and operate physical testing devices.

## Architecture

### Main PLC

#### Main Extensions

### Controller (slave) PLCs

### Controlled (slave) Extensions and accessories

### Networking

- static IPs so far.

## Main controlling Service

### Functions

- on/off PLCs
- install `evok` or `evok-node` on PLC (from repository or hot build)
- running `evok` or `evok-node` based on given configuration
- error simulation
- access to state of controlled endpoints (or sniffing)

### Controlling main PLC I/O and buses

- Don't use evok or evok-node - use sysfs instead

### Messaging

- just local port and WS messaging is interface to the service
- consumer must have SSH connection to the master
- define message structure here

### Accessing slave PLCs

#### From main PLC (for controlling service)

- SSH (keys auth)

#### From elswhere

- tunneling open apis on slaves thru 
- ofering connection strings (over messaging)
- auth is based on SSH (same as accessing messagin)