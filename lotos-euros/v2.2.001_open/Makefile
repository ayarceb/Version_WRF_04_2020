#
# Makefile for source directory.
#

help:
	@echo " "
	@echo " Usage:"
	@echo "   make clean          # remove temporary jb.* files"
	@echo " "

clean: clean-pyc clean-ttb
	/bin/rm -f setup_le*.*.log
	/bin/rm -f jb.[0-9]*.*

clean-pyc:
	/bin/rm -f `find . -type f -name '*.pyc'`
	/bin/rm -f -r `find . -type d -name '__pycache__'`

clean-ttb:
	/bin/rm -f tmp-ttb-*


