.PHONY: skills freeze install-skills clean

skills:
	python3 skills.py clone

freeze:
	python3 skills.py freeze

install-skills:
	python3 skills.py install-skills

clean:
	python3 skills.py clean
