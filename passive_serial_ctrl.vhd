library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity passive_serial_ctrl is

    generic (

        ------------------------------------------------------------
        -- System clock
        ------------------------------------------------------------
        CLK_FREQ_HZ : integer := 100_000_000;

        ------------------------------------------------------------
        -- Passive Serial DCLK
        ------------------------------------------------------------
        DCLK_HZ : integer := 10_000_000;

        ------------------------------------------------------------
        -- nCONFIG LOW duration in system clocks
        --
        -- Simulation can use 20.
        -- Hardware value should follow actual device timing.
        ------------------------------------------------------------
        NCONFIG_LOW_CYCLES : integer := 1000;

        ------------------------------------------------------------
        -- Generic timeout
        ------------------------------------------------------------
        TIMEOUT_CYCLES : integer := 1_000_000
    );

    port (

        ------------------------------------------------------------
        -- System
        ------------------------------------------------------------
        clk    : in std_logic;
        resetn : in std_logic;


        ------------------------------------------------------------
        -- Command
        ------------------------------------------------------------
        start : in std_logic;


        ------------------------------------------------------------
        -- FIFO
        ------------------------------------------------------------
        fifo_q     : in  std_logic_vector(7 downto 0);
        fifo_empty : in  std_logic;
        fifo_rdreq : out std_logic;


        ------------------------------------------------------------
        -- ASMI has completed requested address range
        ------------------------------------------------------------
        flash_done : in std_logic;


        ------------------------------------------------------------
        -- Passive Serial outputs
        ------------------------------------------------------------
        nconfig : out std_logic;
        dclk    : out std_logic;
        data0   : out std_logic;


        ------------------------------------------------------------
        -- Cyclone 10 LP status
        ------------------------------------------------------------
        nstatus   : in std_logic;
        conf_done : in std_logic;
        init_done : in std_logic;


        ------------------------------------------------------------
        -- Status
        ------------------------------------------------------------
        busy       : out std_logic;
        done       : out std_logic;
        error      : out std_logic;

        error_code :
            out std_logic_vector(3 downto 0)

    );

end entity;



architecture rtl of passive_serial_ctrl is


    ----------------------------------------------------------------
    -- State machine
    ----------------------------------------------------------------

    type state_t is (

        S_IDLE,

        S_NCONFIG_LOW,
        S_WAIT_NSTATUS_LOW,

        S_RELEASE_NCONFIG,
        S_WAIT_NSTATUS_HIGH,

        S_FIFO_READ,
        S_FIFO_WAIT,
        S_FIFO_LOAD,

        S_DATA_SETUP,
        S_DCLK_HIGH,

        S_WAIT_CONF_DONE,

        S_EXTRA_SETUP,
        S_EXTRA_HIGH,

        S_WAIT_INIT_DONE,

        S_DONE,
        S_ERROR
    );

    signal state : state_t := S_IDLE;


    ----------------------------------------------------------------
    -- Serializer
    ----------------------------------------------------------------

    signal tx_byte : std_logic_vector(7 downto 0) := (others => '0');

    signal bit_count : integer range 0 to 7 := 0;


    ----------------------------------------------------------------
    -- Outputs
    ----------------------------------------------------------------

    signal nconfig_i : std_logic := '1';
    signal dclk_i    : std_logic := '0';
    signal data0_i   : std_logic := '0';


    ----------------------------------------------------------------
    -- Target status synchronizers
    ----------------------------------------------------------------

    signal nstatus_meta : std_logic := '1';
    signal nstatus_sync : std_logic := '1';

    signal conf_meta : std_logic := '0';
    signal conf_sync : std_logic := '0';

    signal init_meta : std_logic := '0';
    signal init_sync : std_logic := '0';


    ----------------------------------------------------------------
    -- Start edge detection
    ----------------------------------------------------------------

    signal start_d     : std_logic := '0';
    signal start_pulse : std_logic := '0';


    ----------------------------------------------------------------
    -- DCLK timing
    ----------------------------------------------------------------

    constant HALF_DIV : integer := CLK_FREQ_HZ / (2 * DCLK_HZ);

    signal half_count : integer range 0 to HALF_DIV-1 := 0;


    ----------------------------------------------------------------
    -- nCONFIG counter
    ----------------------------------------------------------------

    signal cfg_count : integer range 0 to NCONFIG_LOW_CYCLES := 0;


    ----------------------------------------------------------------
    -- Timeout counter
    ----------------------------------------------------------------

    signal timeout_count : integer range 0 to TIMEOUT_CYCLES := 0;


    ----------------------------------------------------------------
    -- Extra falling edge counter
    ----------------------------------------------------------------

    signal extra_count : integer range 0 to 2 := 0;


begin


    ----------------------------------------------------------------
    -- Physical outputs
    ----------------------------------------------------------------

    nconfig <= nconfig_i;
    dclk    <= dclk_i;
    data0   <= data0_i;


    ----------------------------------------------------------------
    -- Start edge detector
    ----------------------------------------------------------------

    start_proc : process(clk)
    begin

        if rising_edge(clk) then

            if resetn = '0' then

                start_d     <= '0';
                start_pulse <= '0';

            else

                start_pulse <=
                    start and not start_d;

                start_d <= start;

            end if;

        end if;

    end process;


    ----------------------------------------------------------------
    -- Synchronize target signals
    ----------------------------------------------------------------

    sync_proc : process(clk)
    begin

        if rising_edge(clk) then

            if resetn = '0' then

                nstatus_meta <= '1';
                nstatus_sync <= '1';

                conf_meta <= '0';
                conf_sync <= '0';

                init_meta <= '0';
                init_sync <= '0';

            else

                nstatus_meta <= nstatus;
                nstatus_sync <= nstatus_meta;

                conf_meta <= conf_done;
                conf_sync <= conf_meta;

                init_meta <= init_done;
                init_sync <= init_meta;

            end if;

        end if;

    end process;


    ----------------------------------------------------------------
    -- Main FSM
    ----------------------------------------------------------------

    main_proc : process(clk)
    begin

        if rising_edge(clk) then

            --------------------------------------------------------
            -- pulse defaults
            --------------------------------------------------------

            fifo_rdreq <= '0';
            done       <= '0';


            if resetn = '0' then

                state <= S_IDLE;

                nconfig_i <= '1';
                dclk_i    <= '0';
                data0_i   <= '0';

                busy  <= '0';
                error <= '0';

                error_code <= "0000";

                bit_count     <= 0;
                half_count    <= 0;
                cfg_count     <= 0;
                timeout_count <= 0;
                extra_count   <= 0;


            else

                case state is


                    ------------------------------------------------
                    -- IDLE
                    ------------------------------------------------

                    when S_IDLE =>

                        busy       <= '0';
                        error      <= '0';
                        error_code <= "0000";

                        nconfig_i <= '1';
                        dclk_i    <= '0';
                        data0_i   <= '0';

                        bit_count     <= 0;
                        half_count    <= 0;
                        cfg_count     <= 0;
                        timeout_count <= 0;
                        extra_count   <= 0;


                        if start_pulse = '1' then

                            report
                                "CTRL: CONFIGURATION START"
                                severity note;

                            busy <= '1';

                            nconfig_i <= '0';

                            state <= S_NCONFIG_LOW;

                        end if;



                    ------------------------------------------------
                    -- Hold nCONFIG low
                    ------------------------------------------------

                    when S_NCONFIG_LOW =>

                        nconfig_i <= '0';
                        dclk_i    <= '0';


                        if cfg_count =
                           NCONFIG_LOW_CYCLES-1 then

                            cfg_count <= 0;

                            report
                                "CTRL: nCONFIG LOW PERIOD COMPLETE"
                                severity note;

                            state <= S_WAIT_NSTATUS_LOW;

                        else

                            cfg_count <= cfg_count + 1;

                        end if;



                    ------------------------------------------------
                    -- Wait for nSTATUS LOW
                    ------------------------------------------------

                    when S_WAIT_NSTATUS_LOW =>

                        nconfig_i <= '0';
                        dclk_i    <= '0';


                        if nstatus_sync = '0' then

                            report
                                "CTRL: nSTATUS LOW DETECTED"
                                severity note;

                            timeout_count <= 0;

                            state <= S_RELEASE_NCONFIG;


                        elsif timeout_count =
                              TIMEOUT_CYCLES-1 then

                            error <= '1';

                            error_code <= "0001";

                            state <= S_ERROR;


                        else

                            timeout_count <=
                                timeout_count + 1;

                        end if;



                    ------------------------------------------------
                    -- Release nCONFIG
                    ------------------------------------------------

                    when S_RELEASE_NCONFIG =>

                        nconfig_i <= '1';
                        dclk_i    <= '0';

                        timeout_count <= 0;

                        report
                            "CTRL: nCONFIG RELEASED HIGH"
                            severity note;

                        state <= S_WAIT_NSTATUS_HIGH;



                    ------------------------------------------------
                    -- Wait target ready
                    ------------------------------------------------

                    when S_WAIT_NSTATUS_HIGH =>

                        dclk_i <= '0';


                        if nstatus_sync = '1' then

                            report
                                "CTRL: nSTATUS HIGH - TARGET READY"
                                severity note;

                            timeout_count <= 0;

                            state <= S_FIFO_READ;


                        elsif timeout_count =
                              TIMEOUT_CYCLES-1 then

                            error <= '1';

                            error_code <= "0010";

                            state <= S_ERROR;


                        else

                            timeout_count <=
                                timeout_count + 1;

                        end if;



                    ------------------------------------------------
                    -- Request next byte
                    ------------------------------------------------

                    when S_FIFO_READ =>

                        dclk_i <= '0';


                        if nstatus_sync = '0' then

                            error <= '1';

                            error_code <= "0011";

                            state <= S_ERROR;


                        elsif fifo_empty = '0' then

                            fifo_rdreq <= '1';

                            state <= S_FIFO_WAIT;


                        elsif flash_done = '1' then

                            ------------------------------------------------
                            -- All ASMI data transferred
                            -- and FIFO completely drained
                            ------------------------------------------------

                            timeout_count <= 0;

                            state <= S_WAIT_CONF_DONE;

                        end if;



                    ------------------------------------------------
                    -- synchronous FIFO latency
                    ------------------------------------------------

                    when S_FIFO_WAIT =>

                        state <= S_FIFO_LOAD;



                    ------------------------------------------------
                    -- Capture FIFO Q
                    ------------------------------------------------

                    when S_FIFO_LOAD =>

                        tx_byte <= fifo_q;

                        bit_count  <= 0;
                        half_count <= 0;

                        state <= S_DATA_SETUP;



                    ------------------------------------------------
                    -- DATA0 low phase / setup phase
                    ------------------------------------------------

                    when S_DATA_SETUP =>

                        dclk_i <= '0';

                        ------------------------------------------------
                        -- IMPORTANT:
                        -- RBF byte transmitted LSB-first
                        ------------------------------------------------

                        data0_i <= tx_byte(bit_count);


                        if nstatus_sync = '0' then

                            error <= '1';

                            error_code <= "0011";

                            state <= S_ERROR;


                        elsif half_count =
                              HALF_DIV-1 then

                            half_count <= 0;

                            ------------------------------------------------
                            -- Rising edge occurs here
                            ------------------------------------------------

                            dclk_i <= '1';

                            state <= S_DCLK_HIGH;


                        else

                            half_count <=
                                half_count + 1;

                        end if;



                    ------------------------------------------------
                    -- DCLK high phase
                    ------------------------------------------------

                    when S_DCLK_HIGH =>

                        dclk_i <= '1';


                        if nstatus_sync = '0' then

                            error <= '1';

                            error_code <= "0011";

                            state <= S_ERROR;


                        elsif half_count =
                              HALF_DIV-1 then

                            half_count <= 0;

                            ------------------------------------------------
                            -- Falling edge
                            ------------------------------------------------

                            dclk_i <= '0';


                            if bit_count = 7 then

                                ------------------------------------------------
                                -- Byte finished
                                ------------------------------------------------

                                state <= S_FIFO_READ;

                            else

                                ------------------------------------------------
                                -- Next bit
                                ------------------------------------------------

                                bit_count <= bit_count + 1;

                                state <= S_DATA_SETUP;

                            end if;


                        else

                            half_count <=
                                half_count + 1;

                        end if;



                    ------------------------------------------------
                    -- Wait for CONF_DONE
                    ------------------------------------------------

                    when S_WAIT_CONF_DONE =>

                        dclk_i <= '0';


                        if nstatus_sync = '0' then

                            error <= '1';

                            error_code <= "0011";

                            state <= S_ERROR;


                        elsif conf_sync = '1' then

                            report
                                "CTRL: CONF_DONE HIGH"
                                severity note;

                            extra_count <= 0;
                            half_count  <= 0;

                            timeout_count <= 0;

                            state <= S_EXTRA_SETUP;


                        elsif timeout_count =
                              TIMEOUT_CYCLES-1 then

                            error <= '1';

                            error_code <= "0100";

                            state <= S_ERROR;


                        else

                            timeout_count <=
                                timeout_count + 1;

                        end if;



                    ------------------------------------------------
                    -- Extra DCLK low/setup
                    ------------------------------------------------

                    when S_EXTRA_SETUP =>

                        dclk_i <= '0';


                        if half_count =
                           HALF_DIV-1 then

                            half_count <= 0;

                            dclk_i <= '1';

                            state <= S_EXTRA_HIGH;


                        else

                            half_count <=
                                half_count + 1;

                        end if;



                    ------------------------------------------------
                    -- Extra DCLK high -> falling edge
                    ------------------------------------------------

                    when S_EXTRA_HIGH =>

                        dclk_i <= '1';


                        if half_count =
                           HALF_DIV-1 then

                            half_count <= 0;

                            ------------------------------------------------
                            -- Extra falling edge occurs
                            ------------------------------------------------

                            dclk_i <= '0';


                            if extra_count = 1 then

                                report
                                    "CTRL: TWO EXTRA DCLK FALLING EDGES COMPLETE"
                                    severity note;

                                timeout_count <= 0;

                                state <= S_WAIT_INIT_DONE;


                            else

                                extra_count <=
                                    extra_count + 1;

                                state <= S_EXTRA_SETUP;

                            end if;


                        else

                            half_count <=
                                half_count + 1;

                        end if;



                    ------------------------------------------------
                    -- Wait INIT_DONE
                    ------------------------------------------------

                    when S_WAIT_INIT_DONE =>

                        dclk_i <= '0';


                        if init_sync = '1' then

                            report
                                "CTRL: INIT_DONE HIGH"
                                severity note;

                            state <= S_DONE;


                        elsif timeout_count =
                              TIMEOUT_CYCLES-1 then

                            error <= '1';

                            error_code <= "0101";

                            state <= S_ERROR;


                        else

                            timeout_count <=
                                timeout_count + 1;

                        end if;



                    ------------------------------------------------
                    -- Complete
                    ------------------------------------------------

                    when S_DONE =>

                        busy <= '0';
                        done <= '1';

                        nconfig_i <= '1';
                        dclk_i    <= '0';
                        data0_i   <= '0';

                        state <= S_IDLE;



                    ------------------------------------------------
                    -- Error
                    ------------------------------------------------

                    when S_ERROR =>

                        busy  <= '0';
                        error <= '1';

                        dclk_i  <= '0';
                        data0_i <= '0';

                        ------------------------------------------------
                        -- hold target reset
                        ------------------------------------------------

                        nconfig_i <= '0';


                        if start_pulse = '1' then

                            error <= '0';

                            error_code <= "0000";

                            cfg_count     <= 0;
                            timeout_count <= 0;

                            state <= S_NCONFIG_LOW;

                        end if;


                end case;

            end if;

        end if;

    end process;

end architecture;