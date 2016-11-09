NAME = ratp

all: $(NAME)

$(NAME):
	mkdir -p obj/ bin/
	gprbuild -P udp.gpr

clean:
	gprclean -P udp.gpr
	make -C narval_ratp/ clean
	rm -rf obj/ bin/ lib/

lib:
	mkdir -p lib/
	make -C narval_ratp/

re: clean all
