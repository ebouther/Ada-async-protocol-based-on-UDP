NAME = ratp

all: $(NAME)

$(NAME):
	mkdir -p obj/ bin/
	gprbuild -P ratp.gpr

clean:
	gprclean -P ratp.gpr
	make -C narval_ratp/ clean
	rm -rf obj/ bin/ lib/

lib:
	mkdir -p lib/
	make -C narval_ratp/

re: clean all
