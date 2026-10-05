library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity simple_fifo is
    generic (
        DATA_WIDTH : integer := 8;
        DEPTH      : integer := 16
    );
    port (
        clk   : in  std_logic;
        reset : in  std_logic;

        data  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        wrreq : in  std_logic;
        rdreq : in  std_logic;

        q     : out std_logic_vector(DATA_WIDTH-1 downto 0);
        empty : out std_logic;
        full  : out std_logic
    );
end entity;


architecture rtl of simple_fifo is

    type mem_t is array (0 to DEPTH-1)
        of std_logic_vector(DATA_WIDTH-1 downto 0);

    signal mem : mem_t := (others => (others => '0'));

    signal wr_ptr : integer range 0 to DEPTH-1 := 0;
    signal rd_ptr : integer range 0 to DEPTH-1 := 0;

    signal count : integer range 0 to DEPTH := 0;

    signal q_i : std_logic_vector(DATA_WIDTH-1 downto 0)
        := (others => '0');

begin

    q <= q_i;

    empty <= '1' when count = 0 else '0';
    full  <= '1' when count = DEPTH else '0';


    process(clk)

        variable do_write : boolean;
        variable do_read  : boolean;

    begin

        if rising_edge(clk) then

            if reset = '1' then

                wr_ptr <= 0;
                rd_ptr <= 0;
                count  <= 0;

                q_i <= (others => '0');

            else

                do_write :=
                    (wrreq = '1') and
                    (count < DEPTH);

                do_read :=
                    (rdreq = '1') and
                    (count > 0);


                ------------------------------------------------
                -- WRITE
                ------------------------------------------------

                if do_write then

                    mem(wr_ptr) <= data;

                    if wr_ptr = DEPTH-1 then
                        wr_ptr <= 0;
                    else
                        wr_ptr <= wr_ptr + 1;
                    end if;

                end if;


                ------------------------------------------------
                -- READ
                ------------------------------------------------

                if do_read then

                    q_i <= mem(rd_ptr);

                    if rd_ptr = DEPTH-1 then
                        rd_ptr <= 0;
                    else
                        rd_ptr <= rd_ptr + 1;
                    end if;

                end if;


                ------------------------------------------------
                -- FIFO count
                ------------------------------------------------

                if do_write and not do_read then

                    count <= count + 1;

                elsif do_read and not do_write then

                    count <= count - 1;

                end if;

            end if;

        end if;

    end process;

end architecture;