extern void *__cxa_allocate_exception(unsigned long);
extern void __cxa_free_exception(void *);
int main(void)
{
    void *exception = __cxa_allocate_exception(1);
    __cxa_free_exception(exception);
}
