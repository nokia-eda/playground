#!/bin/bash
case "$1" in
  Username*) exec echo "$GIT_USERNAME_VAR" ;;
  Password*) exec echo "$GIT_PASSWORD_VAR" ;;
esac