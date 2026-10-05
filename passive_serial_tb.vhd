library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity passive_serial_tb is
end entity;



architecture sim of passive_serial_tb is


    ----------------------------------------------------------------
    -- Clock
    ----------------------------------------------------------------

    constant CLK_PERIOD : time := 10 ns;

    signal clk :
        std_logic := '0';

    signal resetn :
        std_logic := '0';


    ----------------------------------------------------------------
    -- Command
    ----------------------------------------------------------------

    signal cfg_start :
        std_logic := '0';


    ----------------------------------------------------------------
    -- FIFO
    ----------------------------------------------------------------

    signal fifo_data :
        std_logic_vector(7 downto 0)
        := (others => '0');

    signal fifo_wrreq :
        std_logic := '0';

    signal fifo_rdreq :
        std_logic;

    signal fifo_q :
        std_logic_vector(7 downto 0);

    signal fifo_empty :
        std_logic;

    signal fifo_full :
        std_logic;

    signal fifo_reset :
        std_logic;


    ----------------------------------------------------------------
    -- Flash complete
    ----------------------------------------------------------------

    signal flash_done :
        std_logic := '0';


    ----------------------------------------------------------------
    -- Passive Serial
    ----------------------------------------------------------------

    signal nconfig :
        std_logic;

    signal dclk :
        std_logic;

    signal data0 :
        std_logic;


    ----------------------------------------------------------------
    -- Cyclone 10 LP status
    ----------------------------------------------------------------

    signal nstatus :
        std_logic := '1';

    signal conf_done :
        std_logic := '0';

    signal init_done :
        std_logic := '0';


    ----------------------------------------------------------------
    -- Controller status
    ----------------------------------------------------------------

    signal cfg_busy :
        std_logic;

    signal cfg_done :
        std_logic;

    signal cfg_error :
        std_logic;

    signal cfg_error_code :
        std_logic_vector(3 downto 0);


    ----------------------------------------------------------------
    -- Test data
    ----------------------------------------------------------------

    type rbf_array_t is
        array(natural range <>)
        of std_logic_vector(7 downto 0);


    constant RBF_DATA :
        rbf_array_t(0 to 99) := (

        x"00", x"FF", x"02", x"03",
        x"04", x"05", x"06", x"07",
        x"08", x"09", x"0A", x"0B",
        x"0C", x"0D", x"0E", x"0F",

        x"10", x"11", x"12", x"13",
        x"14", x"15", x"16", x"17",
        x"18", x"19", x"1A", x"1B",
        x"1C", x"1D", x"1E", x"1F",

        x"20", x"21", x"22", x"23",
        x"24", x"25", x"26", x"27",
        x"28", x"29", x"2A", x"2B",
        x"2C", x"2D", x"2E", x"2F",

        x"30", x"31", x"32", x"33",
        x"34", x"35", x"36", x"37",
        x"38", x"39", x"3A", x"3B",
        x"3C", x"3D", x"3E", x"3F",

        x"40", x"41", x"42", x"43",
        x"44", x"45", x"46", x"47",
        x"48", x"49", x"4A", x"4B",
        x"4C", x"4D", x"4E", x"4F",

        x"50", x"51", x"52", x"53",
        x"54", x"55", x"56", x"57",
        x"58", x"59", x"5A", x"5B",
        x"5C", x"5D", x"5E", x"5F",

        x"60", x"61", x"62", x"63"
    );


    ----------------------------------------------------------------
    -- RX storage
    ----------------------------------------------------------------

    signal rx_bit_count :
        integer range 0 to 1000 := 0;

    signal rx_bits :
        std_logic_vector(799 downto 0)
        := (others => '0');


    ----------------------------------------------------------------
    -- Extra clocks monitor
    ----------------------------------------------------------------

    signal extra_falling_edges :
        integer range 0 to 10 := 0;


begin


    ----------------------------------------------------------------
    -- 100 MHz clock
    ----------------------------------------------------------------

    clk <= not clk after CLK_PERIOD/2;


    ----------------------------------------------------------------
    -- FIFO reset
    ----------------------------------------------------------------

    fifo_reset <= not resetn;


    ----------------------------------------------------------------
    -- FIFO INSTANCE
    ----------------------------------------------------------------

    U_FIFO : entity work.simple_fifo

        generic map (

            DATA_WIDTH => 8,
            DEPTH      => 16
        )

        port map (

            clk   => clk,
            reset => fifo_reset,

            data  => fifo_data,

            wrreq => fifo_wrreq,
            rdreq => fifo_rdreq,

            q     => fifo_q,

            empty => fifo_empty,
            full  => fifo_full

        );


    ----------------------------------------------------------------
    -- PASSIVE SERIAL CONTROLLER
    ----------------------------------------------------------------

    U_PS : entity work.passive_serial_ctrl

        generic map (

            CLK_FREQ_HZ => 100_000_000,

            DCLK_HZ => 10_000_000,

            --------------------------------------------------------
            -- simulation value
            --------------------------------------------------------

            NCONFIG_LOW_CYCLES => 20,

            TIMEOUT_CYCLES => 100000
        )

        port map (

            clk    => clk,
            resetn => resetn,

            start => cfg_start,

            fifo_q     => fifo_q,
            fifo_empty => fifo_empty,
            fifo_rdreq => fifo_rdreq,

            flash_done => flash_done,

            nconfig => nconfig,
            dclk    => dclk,
            data0   => data0,

            nstatus   => nstatus,
            conf_done => conf_done,
            init_done => init_done,

            busy  => cfg_busy,
            done  => cfg_done,
            error => cfg_error,

            error_code =>
                cfg_error_code

        );


    ----------------------------------------------------------------
    -- MAIN STIMULUS
    ----------------------------------------------------------------

    stim_proc : process
    begin


        resetn   <= '0';
        cfg_start <= '0';


        wait for 200 ns;


        resetn <= '1';


        wait for 200 ns;


        ------------------------------------------------------------
        -- Start command
        ------------------------------------------------------------

        cfg_start <= '1';

        wait for CLK_PERIOD;

        cfg_start <= '0';


        ------------------------------------------------------------
        -- Wait result
        ------------------------------------------------------------

        wait until
            cfg_done = '1'
            or
            cfg_error = '1';


        if cfg_done = '1' then

            report
                "PASS: PASSIVE SERIAL CONFIGURATION COMPLETED"
                severity note;

        else

            report
                "FAIL: PASSIVE SERIAL CONFIGURATION ERROR. CODE = " &
                integer'image(
                    to_integer(
                        unsigned(cfg_error_code)
                    )
                )
                severity error;

        end if;


        wait for 2 us;


        report
            "END OF SIMULATION"
            severity note;


        std.env.stop;


        wait;

    end process;


    ----------------------------------------------------------------
    -- FLASH / ASMI MODEL
    ----------------------------------------------------------------

    flash_proc : process


        procedure write_fifo_byte(

            constant byte_value :
                in std_logic_vector(7 downto 0)

        ) is

        begin


            --------------------------------------------------------
            -- Wait for space
            --------------------------------------------------------

            while fifo_full = '1' loop

                wait until rising_edge(clk);

            end loop;


            --------------------------------------------------------
            -- Write byte
            --------------------------------------------------------

            fifo_data <= byte_value;

            fifo_wrreq <= '1';


            wait until rising_edge(clk);


            fifo_wrreq <= '0';


            --------------------------------------------------------
            -- Simulated ASMI delay
            --------------------------------------------------------

            wait for 20 ns;


        end procedure;


    begin


        fifo_wrreq <= '0';

        fifo_data <=
            (others => '0');

        flash_done <= '0';


        wait until resetn = '1';


        wait until
            rising_edge(cfg_start);


        report
            "FLASH MODEL: STARTING 100 BYTE TRANSFER"
            severity note;


        ------------------------------------------------------------
        -- Write 100 bytes
        ------------------------------------------------------------

        for i in
            RBF_DATA'range
        loop

            write_fifo_byte(
                RBF_DATA(i)
            );

        end loop;


        ------------------------------------------------------------
        -- Entire selected flash range completed
        ------------------------------------------------------------

        wait until rising_edge(clk);


        flash_done <= '1';


        report
            "FLASH MODEL: ALL 100 BYTES WRITTEN"
            severity note;


        wait;

    end process;


    ----------------------------------------------------------------
    -- CYCLONE 10 LP STATUS MODEL
    ----------------------------------------------------------------

    target_status_proc : process
    begin


        nstatus <= '1';


        ------------------------------------------------------------
        -- Detect nCONFIG falling edge
        ------------------------------------------------------------

        wait until falling_edge(nconfig);


        report
            "TARGET: nCONFIG LOW"
            severity note;


        ------------------------------------------------------------
        -- Target pulls nSTATUS LOW
        ------------------------------------------------------------

        wait for 50 ns;


        nstatus <= '0';


        report
            "TARGET: nSTATUS LOW"
            severity note;


        ------------------------------------------------------------
        -- Wait until host releases nCONFIG
        ------------------------------------------------------------

        wait until rising_edge(nconfig);


        report
            "TARGET: nCONFIG HIGH"
            severity note;


        ------------------------------------------------------------
        -- Target recovery/POR delay model
        ------------------------------------------------------------

        wait for 100 ns;


        nstatus <= '1';


        report
            "TARGET: nSTATUS HIGH"
            severity note;


        wait;

    end process;


    ----------------------------------------------------------------
    -- Capture configuration DATA0
    ----------------------------------------------------------------

    rx_proc : process(dclk)
    begin


        if rising_edge(dclk) then


            if rx_bit_count < 800 then


                rx_bits(
                    rx_bit_count
                ) <= data0;


                rx_bit_count <=
                    rx_bit_count + 1;


            end if;


        end if;


    end process;


    ----------------------------------------------------------------
    -- CONF_DONE MODEL
    ----------------------------------------------------------------

    conf_done_proc : process
    begin


        conf_done <= '0';


        wait until
            rx_bit_count = 800;


        report
            "TARGET: ALL 800 CONFIGURATION BITS RECEIVED"
            severity note;


        wait for 100 ns;


        conf_done <= '1';


        report
            "TARGET: CONF_DONE HIGH"
            severity note;


        wait;

    end process;


    ----------------------------------------------------------------
    -- Count falling DCLK after CONF_DONE
    ----------------------------------------------------------------

    extra_clock_monitor :
        process(dclk)
    begin


        if falling_edge(dclk) then


            if conf_done = '1'
               and init_done = '0'
            then


                if extra_falling_edges < 10 then

                    extra_falling_edges <=
                        extra_falling_edges + 1;

                end if;


            end if;


        end if;


    end process;


    ----------------------------------------------------------------
    -- INIT_DONE MODEL
    ----------------------------------------------------------------

    init_done_proc : process
    begin


        init_done <= '0';


        wait until
            conf_done = '1';


        ------------------------------------------------------------
        -- Wait for exactly the required additional clocks
        ------------------------------------------------------------

        wait until
            extra_falling_edges >= 2;


        wait for 100 ns;


        init_done <= '1';


        report
            "TARGET: INIT_DONE HIGH AFTER TWO EXTRA DCLK FALLING EDGES"
            severity note;


        wait;

    end process;


    ----------------------------------------------------------------
    -- Data checker
    ----------------------------------------------------------------

    checker_proc : process


        variable rx_byte :
            std_logic_vector(7 downto 0);


    begin


        wait until
            rx_bit_count = 800;


        wait for 200 ns;


        ------------------------------------------------------------
        -- Rebuild 100 bytes
        ------------------------------------------------------------

        for byte_idx in 0 to 99 loop


            for bit_idx in 0 to 7 loop


                rx_byte(bit_idx) :=

                    rx_bits(
                        byte_idx * 8
                        +
                        bit_idx
                    );


            end loop;


            --------------------------------------------------------
            -- Compare
            --------------------------------------------------------

            assert
                rx_byte =
                RBF_DATA(byte_idx)

                report

                    "DATA MISMATCH AT BYTE " &
                    integer'image(byte_idx) &

                    " EXPECTED=" &
                    integer'image(
                        to_integer(
                            unsigned(
                                RBF_DATA(byte_idx)
                            )
                        )
                    ) &

                    " RECEIVED=" &
                    integer'image(
                        to_integer(
                            unsigned(rx_byte)
                        )
                    )

                severity error;


        end loop;


        report
            "PASS: ALL 100 RBF BYTES RECEIVED CORRECTLY LSB-FIRST"
            severity note;


        wait;

    end process;


    ----------------------------------------------------------------
    -- Progress
    ----------------------------------------------------------------

    progress_proc : process
    begin


        wait until
            rx_bit_count = 80;

        report
            "PROGRESS: 10 BYTES RECEIVED"
            severity note;


        wait until
            rx_bit_count = 200;

        report
            "PROGRESS: 25 BYTES RECEIVED"
            severity note;


        wait until
            rx_bit_count = 400;

        report
            "PROGRESS: 50 BYTES RECEIVED"
            severity note;


        wait until
            rx_bit_count = 600;

        report
            "PROGRESS: 75 BYTES RECEIVED"
            severity note;


        wait until
            rx_bit_count = 800;

        report
            "PROGRESS: 100 BYTES RECEIVED"
            severity note;


        wait;

    end process;


end architecture;