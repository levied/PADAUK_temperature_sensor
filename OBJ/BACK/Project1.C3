#include "extern.h"

/* Definitions */
// For Working mode
#define MODE_NORMAL    	0
#define MODE_ARLAM    	1
#define MODE_SLEEP    	2
#define MODE_TEST    	3
// For buzzer mode
#define BUZZER_OFF    	0
#define BUZZER_ALARM  	1
#define BUZZER_LOW_BAT  2
// For led mode
#define LED_NORMAL    	0
#define LED_ALARM    	1
#define LED_LOW_BAT    	2
// For ADC
#define ADC_ENABLE      0x80 // Bit 7
#define ADC_START       0x40 // Bit 6
#define CH_PA0          0x28 // 1010 shifted to bits 5-2
#define CH_PA4          0x24 // 1001 shifted to bits 5-2
#define NTC            	0x28 // CH_PA0 for temperature measurement NCT pin
#define BUTTON_VR    	0x24 // CH_PA4 for temperature setting varistor pin and button
// For OUTPUT
#define POWER_ON_ADC()  PA.5 = 1; // Turn on power for NTC and VR pins
#define POWER_OFF_ADC() PA.5 = 0; // Turn off power for NTC and VR pins
#define OUTPUT_ON()    	PA.6 = 1; // Turn on Relay and RF signal
#define OUTPUT_OFF()  	PA.6 = 0; // Turn off Relay and RF signal
#define LED_ON()    	PA.7 = 1; // Turn on LED
#define LED_OFF()    	PA.7 = 0; // Turn off LED
// For Temperature check
#define VR_MAX_VALUE  	200
/* Variables */
// For system
WORD tick_100ms[2];
WORD tick_buzzer;
// For mode
BYTE working_mode = MODE_NORMAL;
BYTE buzzer_mode = BUZZER_OFF;
BYTE led_mode = LED_NORMAL;
// For Temperature measurement
BYTE adc_value = 0;
BYTE setting_alarm_value = 40;
// For Temperature measurement


/* Functions */

// Delay function
void delay_ms(WORD stime)
{
	while(stime--)
	{
	.delay 1000;
	}
}

// Function to read the ADC value
BYTE ADC_Read(BYTE channel) 
{
	// 1. Configure the ADC channel in ADCC register
	// channel should be passed based on the pin mappings in your header
	ADCC = ADC_ENABLE | (channel); // Set bit 7 (Enable) and channel bits [5:1]

	// 2. Start the conversion
	ADCC |= ADC_START; // Set the Start bit (AD_START)

	// 3. Wait for the conversion to complete
	// ADCC bit 6 is automatically cleared by hardware when done
	while (ADCC & ADC_START) 
	{
	    // Wait...
	}

	// 4. Return the 8-bit result
	return ADCR;
}

// Function for PWM
void PWM_Init(void)
{
	PAC.3 = 1;                   // PA3 as output
	TM2CT = 0;                   // Reset counter
	// Frequency: 4MHz / 4 (S2) / 256 = 3.9kHz
	TM2S = 0b0_00_00100;   // 8-bit, S1=1, S2=4
	// Duty Cycle: 128/256 = 50%
	TM2B = 128;            
	// Mode: Fsys, Output PA3, PWM Mode
	TM2C = 0b0001_10_1_0; 
}

void PWM_On(void)
{
    TM2C |= 0b0000_10_0_0; // Set bit 3 to enable PA3 output
}

void PWM_Off(void)
{
    TM2C &= 0b1111_01_1_1; // Clear bit 3 to disable PA3 output
    PA.3 = 0;                    // Ensure pin is LOW
}

// Function for GPIO output
void Output_Init(void)
{
	// Init OUTPUT and LED
	PA = 0b0000_0000;  // Standardize binary literals
	PAC = 0b1110_0000; // Set input/output PA5: enable power supply for NTC, VR; PA6: OUTPUT; PA7: LED
	PAPH = 0b0000_0000; // Disable all pull-high on PA
	PADIER = 0b0000_0000; // Disable digital input on PA
	POWER_OFF_ADC();
	OUTPUT_OFF();
	LED_OFF();
}

// Function for Timer 3
void Tim3_Init(void)
{
	// Set clock = SYSCLK, period mode
	TM3C = 0x12;
	// 8 bit, clock prescalar = 64, clock scalar = 24 -> devider = prescalar*(scalar + 1) = 64*25 = 1600
	// Timer 3 clock = 4Mhz/1600 = 2500
	TM3S = 0x78;
	// TM3B: Set bound to 250 for 100ms
	TM3B = 250;
	// Enable Timer3
	TM3C |= 0x01; 
}

// Function for interrupt
void Interrupt(void)
{
    pushaf;
    if (Intrq.TM3) 
    {
        // Timer 3 Interrupt occurs every 1ms
        tick_100ms[0]++;
		if(tick_100ms[0] == 0xFFFF)
		{
			tick_100ms[1]++;
		}
        // Clear Timer 3 interrupt request flag
        Intrq.TM3 = 0; 
    }
    popaf;
}

// Main function
void FPPA0 (void)
{
	// Set system clock
	.ADJUST_IC SYSCLK=IHRC/4;
	// Init peripherals
	PWM_Init();
	Output_Init();
	Tim3_Init();

	// --- Interrupt Setup ---
	IntEn.TM3 = 1;      // Enable Timer 3 Interrupt
	Intrq = 0;          // Clear all interrupt requests
	engint;             // Enable Global Interrupts

    while (1)
    {
	    //////////////////////////// Working mode process ////////////////////////////
	    if(working_mode == MODE_NORMAL)
	    {
			// ADC process
			POWER_ON_ADC(); // On power supply for ADC pins
			delay_ms(10); // delay for fill capacitor
			// Check NCT, Measure Temperature
			adc_value = ADC_Read(NTC); // Get ADC on NTC pin
			if(adc_value > setting_alarm_value)
			{
				OUTPUT_ON();   // On Relay and RF
				buzzer_mode = BUZZER_ALARM;
				led_mode = LED_ALARM;
			}
			// Check BUTTON_VR for setting temperature value
			adc_value = ADC_Read(BUTTON_VR); // Get ADC on BUTTON_VR pin
			if(adc_value < VR_MAX_VALUE) // Varistor divider voltage
			{
				setting_alarm_value = adc_value;
			}
			else // Button is pressed, button short VCC to adc pin
			{
				working_mode = MODE_TEST;
			}
			POWER_OFF_ADC(); // Off power supply for ADC pins
	    }
	    else if(working_mode == MODE_TEST)
	    {
			POWER_ON_ADC(); // On power supply for ADC pins
			adc_value = ADC_Read(BUTTON_VR); // Get ADC on BUTTON_VR pin
			if(adc_value < VR_MAX_VALUE) // Button is released
			{
			// out the testing mode if button is released
			working_mode = MODE_NORMAL;
			}
			POWER_OFF_ADC(); // Off power supply for ADC pins
	    }
	    //////////////////////////// Buzzer mode process ////////////////////////////
	    if(buzzer_mode == BUZZER_ALARM)
	    {
	     	PWM_On();
	    }
	    else if(buzzer_mode == BUZZER_LOW_BAT)
	    {
	      	PWM_On();
	    }
	    else
	    {
			PWM_Off();
	    }
    }
}