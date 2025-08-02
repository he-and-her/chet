.PHONY: test coveralls run

-include .env

ifeq (,$(wildcard .env))
  $(warning .env file not found, skipping export)
else
  export $(shell sed 's/=.*//' .env)
endif

run:
	iex -S mix phx.server

test:
	MIX_ENV=test mix ecto.reset || true
	mix test

coveralls:
	mix coveralls.html || true
	open cover/excoveralls.html
