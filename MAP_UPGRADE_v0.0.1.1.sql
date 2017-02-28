/*
RELEASE DB SCRIPTS
------------------
PROJECT : MAP UPGRADE 
VERSION	: 0.0.1.1
DATE	: 01-DEC-2016
AUTHOR	: S.ARUN
SCHEMA	: PORTAL
CONTENT	: 	
			
			Tables 
			1.DB_ERROR_MESSAGES
			
			Packages 
			1. Exception Handler Package (EXCEPTION_PKG)
			
			Functions
			1. GET_ORDINATE_VALUE
					
*/

whenever sqlerror exit sql.sqlcode

--grant privileges
connect sys/SystemPwd1 as sysdba
GRANT SELECT ON V_$SESSION TO portal;
--------------------------------------------------------
--  DDL for Table DB_ERROR_MESSAGES
--------------------------------------------------------
create table db_error_messages
(
  error_message_id   number(10)                 not null,
  error_date         timestamp(6)               default systimestamp          not null,
  error_user         varchar2(30 byte)          default user                  not null,
  message_type       varchar2(15 byte),
  package_name       varchar2(250 byte),
  procedure_or_line  varchar2(30 byte),
  error_code         varchar2(10 byte),
  error_message1     varchar2(4000 byte),
  error_message2     varchar2(4000 byte),
  error_message3     varchar2(4000 byte),
  error_message4     varchar2(4000 byte)
);


CREATE UNIQUE INDEX UK_ERROR_MESSAGES ON DB_ERROR_MESSAGES
(ERROR_MESSAGE_ID);

-- Create the sequence used for the ERROR_MESSAGES PK

CREATE SEQUENCE ERROR_MESSAGE_SEQ
  START WITH 1;

-------------------------------------------------------------------------------------------------------------------

--------------------------------------------------------
--  Package EXCEPTION_PKG
--------------------------------------------------------
create or replace PACKAGE EXCEPTION_PKG 
as

   /* ***********************************************************************************
   *
   * Package: exception_pkg
   *
   * Purpose: Exception handling functionality
   *
   * Author:  Arun.S
   *
   * Revision History:
   *
   ***************************************************************************************** */

   /*=====================================================================
   * Constants
   *=====================================================================*/

   c_InfMsg    constant db_error_messages.message_type%type := 'Informational';
   c_WarnMsg   constant db_error_messages.message_type%type := 'Warning';
   c_ErrMsg    constant db_error_messages.message_type%type := 'Fatal Error';
   c_DbgMsg    constant db_error_messages.message_type%type := 'Debug';
   c_MaintMsg  constant db_error_messages.message_type%type := 'Maintenance';

   /*=====================================================================
   * Exception Definitions
   *=====================================================================*/

   unhandled_except              constant number := -20001;
   unhandled_except_exception    exception;
   pragma exception_init(unhandled_except_exception, -20001);

   bad_parameter                 constant number := -20002;
   bad_parameter_exception       exception;
   pragma exception_init(bad_parameter_exception, -20002);

   assertion_failure             constant number := -20003;
   assertion_failure_exception   exception;
   pragma exception_init(assertion_failure_exception, -20003);

   /*=====================================================================
   * Procedures
   *=====================================================================*/

   procedure write_exception_info( p_msg_type   db_error_messages.message_type%type
                                 , p_pkg_name   db_error_messages.package_name%type
                                 , p_func_name  db_error_messages.procedure_or_line%type
                                 , p_error_code db_error_messages.error_code%type
                                 , p_msg1       db_error_messages.error_message2%type
                                 , p_msg2       db_error_messages.error_message3%type
                                 , p_msg3       db_error_messages.error_message4%type
                                 );

   procedure who_called_me( p_owner      out varchar2,
                            p_name       out varchar2,
                            p_lineno     out number,
                            p_caller_t   out varchar2,
                            p_my_depth   in number default 3
                          );

   procedure throw( p_exception in number
                  , p_extra_msg in varchar2 default NULL
                  , raise_exception boolean default TRUE
                  );

end exception_pkg;
/

create or replace PACKAGE BODY EXCEPTION_PKG 
as

   /* ***********************************************************************************
   *
   * Package: exception_pkg
   *
   * Purpose: Exception handling functionality
   *
   * Author:  Arun.S
   *
    **************************************************************************************/

   /*=====================================================================
   * Types
   *=====================================================================*/

   type myArray is table of varchar2(255) index by binary_integer;

   /*=====================================================================
   * Globals
   *=====================================================================*/

   err_msgs  myArray;

   /*=====================================================================
   * Procedures
   *=====================================================================*/

   procedure who_called_me( p_owner      out varchar2,
                            p_name       out varchar2,
                            p_lineno     out number,
                            p_caller_t   out varchar2,
                            p_my_depth   in number default 3
                          )
   as
       call_stack  varchar2(4096) default dbms_utility.format_call_stack;
       n           number;
       found_stack BOOLEAN default FALSE;
       line        varchar2(255);
       cnt         number := 0;
   begin

       loop
           n := instr( call_stack, chr(10) );
           exit when ( cnt = p_my_depth or n is NULL or n = 0 );

           line := substr( call_stack, 1, n-1 );
           call_stack := substr( call_stack, n+1 );

           if ( NOT found_stack ) then
               if ( line like '%handle%number%name%' ) then
                   found_stack := TRUE;
               end if;
           else
               cnt := cnt + 1;
               -- cnt = 1 is ME
               -- cnt = 2 is MY Caller
               -- cnt = 3 is Their Caller
               if ( cnt = p_my_depth ) then
                  begin
                   p_lineno := to_number(substr( line, 13, 6 ));
                   -------------added custom exception(Arun)
                   exception 
                   when others then 
                   p_lineno := 1;
                   end;
                   ----------------------------------------
                   
                   line   := substr( line, 21 );
                   if ( line like 'pr%' ) then
                       n := length( 'procedure ' );
                   elsif ( line like 'fun%' ) then
                       n := length( 'function ' );
                   elsif ( line like 'package body%' ) then
                       n := length( 'package body ' );
                   elsif ( line like 'pack%' ) then
                       n := length( 'package ' );
                   elsif ( line like 'anonymous%' ) then
                       n := length( 'anonymous block ' );
                   else
                       n := null;
                   end if;
                   if ( n is not null ) then
                      p_caller_t := ltrim(rtrim(upper(substr( line, 1, n-1 ))));
                   else
                      p_caller_t := 'TRIGGER';
                   end if;

                   line := substr( line, nvl(n,1) );
                   n := instr( line, '.' );
                   p_owner := ltrim(rtrim(substr( line, 1, n-1 )));
                   p_name  := ltrim(rtrim(substr( line, n+1 )));
               end if;
           end if;
       end loop;

   end who_called_me;

   /*=====================================================================
   * PRIVATE function: get_session_info
   * purpose:   Returns a formatted string containing some information
   *            about the current session
   *=====================================================================*/

   function get_session_info return varchar2 is

      l_sessinfo     varchar2(2000);

   begin

      select
         '[SID = ' || sid || '], ' ||
         '[SERIAL# = ' || serial# ||'], ' ||
         '[MACHINE = ' || replace(machine,chr(0),'') || '], ' ||
         '[OSUSER = ' || osuser || '], ' ||
         '[PROGRAM = ' || program || '], ' ||
         '[LOGON_TIME = ' || to_char(logon_time,'mm/dd/yyyy hh:mi:ss') || ']' into l_sessinfo
      from v$session
      WHERE audsid = SYS_CONTEXT('userenv','sessionid');

      return l_sessinfo;

   end get_session_info;

   /*=====================================================================
   * procedure: write_exception_info
   * purpose:   Call the exception logging routine
   *=====================================================================*/

   procedure write_exception_info( p_msg_type   db_error_messages.message_type%type
                                 , p_pkg_name   db_error_messages.package_name%type
                                 , p_func_name  db_error_messages.procedure_or_line%type
                                 , p_error_code db_error_messages.error_code%type
                                 , p_msg1       db_error_messages.error_message2%type
                                 , p_msg2       db_error_messages.error_message3%type
                                 , p_msg3       db_error_messages.error_message4%type
                                 ) is

   -- This procedure is autonomous from the calling procedure.
   -- i.e The calling procedure does not have to be complete
   -- for this procedure to commit its changes.
   pragma autonomous_transaction;
   l_sessinfo     varchar2(2000);

   begin

      l_sessinfo := get_session_info;

      insert into db_error_messages
         ( error_message_id
         , error_date
         , error_user
         , message_type
         , package_name
         , procedure_or_line
         , error_code
         , error_message1
         , error_message2
         , error_message3
         , error_message4
         )
      values
         ( error_message_seq.nextval
         , sysdate
         , USER
         , p_msg_type
         , p_pkg_name
         , p_func_name
         , p_error_code
         , l_sessinfo
         , p_msg1
         , p_msg2
         , p_msg3
         );

      commit;

   exception
      when others then
         -- We don't want an error logging a message to
         -- cause the application to crash
         return;

   end write_exception_info;

   procedure throw( p_exception in number
                  , p_extra_msg in varchar2 default NULL
                  , raise_exception boolean default TRUE
                  ) is

      l_owner        varchar2(30);
      l_name         varchar2(30);
      l_type         varchar2(30);
      l_line         number;
      l_exception    number;

   begin

     who_called_me( l_owner, l_name, l_line, l_type );
     write_exception_info( c_ErrMsg
                         , l_owner || '.' || l_name
                         , 'Line ' || l_line
                         , p_exception
                         , p_extra_msg
                         , NULL
                         , err_msgs(p_exception)
                         );
    if raise_exception then
     raise_application_error( p_exception
                            , 'Exception at ' || l_type || ' ' ||
                              l_owner || '.' || l_name || '(' || l_line || '). ' ||
                              err_msgs(p_exception       ) || '. ' || p_extra_msg
                            , TRUE );
    end if;

   exception
      -- we will get this when we have an invalid exception code, one
      -- that was not set in the err_msgs array below.  The plsql table
      -- access will raise the NO-DATA-FOUND exception.  We'll catch it,
      -- verify the exception code is in the valid range for raise_application_error
      -- (if not, set to -20000) and then raise the exception with the message
      -- "unknown error"

     when NO_DATA_FOUND then
         if ( p_exception between -20000 and -20999 ) then
            l_exception := p_exception;
         else
            l_exception := -20000;
         end if;

        write_exception_info( c_ErrMsg
                            , l_owner || '.' || l_name
                            , 'Line ' || l_line
                            , p_exception
                            , p_extra_msg
                            , NULL
                            , '**UNKNOWN ERROR**'
                            );
         raise_application_error( l_exception
                                , 'Exception at ' || l_type || ' ' ||
                                  l_owner || '.' || l_name || '(' || l_line || '). ' ||
                                  '**UNKNOWN ERROR**' || '. ' || p_extra_msg
                                , TRUE );

   end throw;

begin

   -- This code is run once per session when this package is first touched

   err_msgs( unhandled_except ) := 'Unhandled exception';
   err_msgs( bad_parameter ) := 'Invalid parameter passed into function or procedure';
   err_msgs( assertion_failure ) := 'Program execution stopped due to assertion failure';

end exception_pkg;
/

---------------------------------------------------------------------------------------------------------------

create or replace function get_ordinate_value
(v_geom sdo_geometry, vPos number default 1) 
return number  
is  
  begin  
  
    if v_geom is null  
    then  
       return null;  
    end if;  
  
    if vPos <1 or vPos >v_geom.sdo_ordinates.count()  
    then  
      return null;  
    end if;  
  
    return round(v_geom.sdo_ordinates(vPos ),8);  
end get_ordinate_value;
  /
---------------------------------------------------------------------------------------------------------------