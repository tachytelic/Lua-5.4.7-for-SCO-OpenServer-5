OUTPUT_FORMAT("elf32-i386", "elf32-i386", "elf32-i386")
OUTPUT_ARCH(i386)
ENTRY(_start)

PHDRS {
  phdr    PT_PHDR    PHDRS ;
  interp  PT_INTERP  ;
  text    PT_LOAD    FLAGS(5) FILEHDR PHDRS ;
  data    PT_LOAD    FLAGS(7) ;
  dynamic PT_DYNAMIC ;
  note    PT_NOTE    ;
}

SECTIONS {
  . = 0x08048000 + SIZEOF_HEADERS;
  .interp      : { *(.interp)              } :interp :text
  .hash        : { *(.hash)               } :text
  .dynsym      : { *(.dynsym)             } :text
  .dynstr      : { *(.dynstr)             } :text
  .rel.dyn     : { *(.rel.dyn)            } :text
  .rel.plt     : { *(.rel.plt)            } :text
  .plt         : ALIGN(16) { *(.plt) *(.plt.got) } :text
  .text        : ALIGN(16) { *(.text) *(.text.*) } :text
  .rodata      : ALIGN(32) { *(.rodata) *(.rodata.*) } :text
  .eh_frame    : ALIGN(4)  { *(.eh_frame) } :text
  /* Reserve a PT_NOTE phdr slot — sco_patch.py rewrites it to point at the
     SCO note bytes it appends. Without this, the linker emits only 5 phdrs
     and the patcher's NOTE entry gets silently truncated. SCO's loader
     requires PT_NOTE with p_filesz=0x1c. */
  .note.sco    : { LONG(0); LONG(0); LONG(0); } :text :note
  . = ALIGN(0x1000);
  .dynamic     : { *(.dynamic)            } :data :dynamic
  .data.rel.ro : ALIGN(32) { *(.data.rel.ro*) } :data
  .got         : ALIGN(4)  { *(.got)      } :data
  .got.plt     : ALIGN(4)  { *(.got.plt)  } :data
  .data        : ALIGN(32) { *(.data) *(.data.*) } :data
  .bss         : ALIGN(32) { *(.bss) *(.bss.*) *(COMMON) } :data
}
