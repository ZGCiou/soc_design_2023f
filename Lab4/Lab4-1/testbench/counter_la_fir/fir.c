#include "fir.h"

void __attribute__ ( ( section ( ".mprjram" ) ) ) initfir() {
	//initial your fir
	for (int i=0; i<N; i++) {
		inputbuffer[N] = 0;
		outputsignal[N] = 0;
	}
}

int* __attribute__ ( ( section ( ".mprjram" ) ) ) fir(){
	initfir();
	//write down your fir
	for (int i=0; i<N; i++) {
		for (int k=0; k<N; k++) {
			if (i-k >= 0)
				outputsignal[i] += inputsignal[i-k] * taps[k];
		}
	}
	return outputsignal;
}
		
