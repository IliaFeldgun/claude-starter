.PHONY: skills freeze install clean

skills:
	python3 skills.py clone

freeze:
	python3 skills.py freeze

install:
	python3 skills.py install

clean:
	python3 skills.py clean
