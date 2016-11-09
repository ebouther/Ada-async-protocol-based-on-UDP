NAME = ratp_cons

all: $(NAME)
	
$(NAME):
	mkdir -p obj/ shared_ali/
	gprbuild -XLIBRARY_TYPE=relocatable -P ratp_cons_lib.gpr

clean:
	gprclean -XLIBRARY_TYPE=relocatable -P ratp_cons_lib.gpr
	rm -rf obj/ shared_ali/

re: clean all
