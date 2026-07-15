# Hardware Strategy

## Phase 0

Platform:

* Raspberry Pi 4

Networking:

* WiFi

Purpose:

* Learn
* Validate
* Build infrastructure

---

## Phase 1

Platform:

* Raspberry Pi 4

Storage:

* External USB SSD

Networking:

* Gigabit Ethernet

Purpose:

* Learn
* Validate
* Build infrastructure

---

## Phase 2

Platform:

Mini PC

Storage:

* NVMe
* SSD
* Optional HDD

Purpose:

* Higher performance
* Additional services
* Better scalability

---

## Hardware Independence

Applications should never depend on specific hardware.

Migration should involve only:

* Moving data
* Cloning the repository
* Deploying containers

No architectural changes should be required.
