# RUMO AO DIPLOMA - jogo do PBL3
# Na placa (DE1-SoC, Linux):   make      e depois   sudo ./diploma
# O driver em Assembly e o mesmo da fase 2 (../driver).

CC      = gcc
CFLAGS  = -O2 -Wall -Wextra -pthread -I../driver
DRIVER  = ../driver/driver_copro.s
OBJS    = jogo.c logica.c fase.c entrada.c efeitos.c

diploma: $(OBJS) ../driver/copro.h $(DRIVER)
	$(CC) $(CFLAGS) -o $@ $(OBJS) $(DRIVER)

clean:
	rm -f diploma
