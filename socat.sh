#!/bin/bash

sudo socat TCP-LISTEN:80,fork TCP:$(minikube ip):80